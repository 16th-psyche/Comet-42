import Foundation
import Observation

nonisolated struct BackendModel: Equatable, Hashable, Identifiable, Sendable {
    let id: String
    let name: String
}

nonisolated struct BackendStatus: Equatable, Sendable {
    enum Phase: Equatable, Sendable {
        case idle
        case checking
        case ready
        case signInRequired
        case notInstalled
        case failed(String)
    }

    var phase: Phase = .idle
    var version: String?
    var executable: URL?
    var models: [BackendModel] = []

    var isReady: Bool { phase == .ready && executable != nil }

    var summary: String {
        switch phase {
        case .idle, .checking: return "Checking…"
        case .ready: return "Ready" + (version.map { " · " + $0 } ?? "")
        case .signInRequired: return "Signed out"
        case .notInstalled: return "Not installed"
        case .failed(let message): return message
        }
    }
}

/// Finds the installed CLIs and asks each who is signed in; never handles a credential itself.
@Observable
final class AIBackends {
    private(set) var statuses: [AIBackend: BackendStatus] = [:]
    /// Codex publishes no catalog to `exec`, so its list is whatever the reader typed in Settings.
    var codexModels: [String] = []
    /// The account's own Codex models, once the app-server has listed them.
    private(set) var codexCatalog: [BackendModel] = []
    @ObservationIgnored private var codexServer: CodexAppServer?
    /// Set when the app-server could not start, so later requests go straight to `codex exec`.
    @ObservationIgnored private var codexUsesExec = false

    let workspace: URL

    init(supportDirectory: URL) {
        workspace = supportDirectory.appending(path: "Workspace", directoryHint: .isDirectory)
        try? PrivateWorkspace.prepare(workspace)
    }

    func status(_ backend: AIBackend) -> BackendStatus { statuses[backend] ?? BackendStatus() }

    func models(for backend: AIBackend) -> [BackendModel] {
        switch backend {
        case .claude: return status(.claude).models
        case .codex:
            let listed = codexCatalog.isEmpty ? codexModels.map { BackendModel(id: $0, name: $0) } : codexCatalog
            return [BackendModel(id: "", name: "Codex Default")] + listed
        }
    }

    func refresh() {
        for backend in AIBackend.allCases {
            statuses[backend] = BackendStatus(phase: .checking)
            let workspace = workspace
            Task {
                let status = await Self.probe(backend, workspace: workspace)
                self.statuses[backend] = status
                // The model list needs the app-server; it starts briefly, then idles out.
                if backend == .codex, status.isReady, let executable = status.executable, !self.codexUsesExec {
                    await self.codexServer(for: executable).refreshModels()
                }
            }
        }
    }

    func provider(for choice: ModelChoice, effort: String?) throws -> any AIProvider {
        let status = status(choice.backend)
        switch status.phase {
        case .notInstalled:
            throw AIProviderError.unavailable(
                "\(choice.backend.title) CLI is not installed. Install it with: "
                    + choice.backend.installHint)
        case .signInRequired:
            throw AIProviderError.unavailable(
                "Sign in first: run `\(choice.backend.signInCommand)` in Terminal.")
        case .checking, .idle:
            throw AIProviderError.unavailable("Still looking for \(choice.backend.title)…")
        case .failed(let message):
            throw AIProviderError.unavailable(message)
        case .ready:
            break
        }
        guard let executable = status.executable else {
            throw AIProviderError.unavailable("\(choice.backend.title) could not be found.")
        }
        switch choice.backend {
        case .claude:
            return ClaudeCLIProvider(
                executable: executable, model: choice.model, effort: effort, workspace: workspace)
        case .codex:
            let exec = CodexCLIProvider(
                executable: executable, model: choice.model, effort: effort, workspace: workspace)
            guard !codexUsesExec else { return exec }
            return CodexAppServerProvider(
                server: codexServer(for: executable), fallback: exec, model: choice.model,
                effort: effort, onFallback: { [weak self] in self?.codexUsesExec = true })
        }
    }

    private func codexServer(for executable: URL) -> CodexAppServer {
        if let codexServer { return codexServer }
        let server = CodexAppServer(executable: executable, workspace: workspace)
        server.onModels = { [weak self] models in self?.codexCatalog = models }
        codexServer = server
        return server
    }

    // MARK: - Probing

    private static let claudeInitializeRequest =
        #"{"type":"control_request","request_id":"comet-models","request":{"subtype":"initialize"}}"#
        + "\n"

    nonisolated private static func probe(
        _ backend: AIBackend, workspace: URL
    ) async -> BackendStatus {
        // Test hook: `COMET_CODEX_PATH` / `COMET_CLAUDE_PATH` point the self-test at a stand-in CLI.
        let override = ProcessInfo.processInfo.environment["COMET_\(backend.command.uppercased())_PATH"]
            .map { URL(fileURLWithPath: $0) }
        let located: URL?
        if let override {
            located = override
        } else {
            located = await ExecutableLocator.locate(
                backend.command, extraHomePaths: backend.extraExecutablePaths)
        }
        guard let executable = located else { return BackendStatus(phase: .notInstalled) }
        let environment = ExecutableLocator.environment(running: executable)
        let versionResult = await CLIProcess.run(
            executable: executable, arguments: ["--version"], workspace: workspace,
            environment: environment)
        guard versionResult.status == 0 else {
            return BackendStatus(
                phase: .failed("The installed command could not run."), executable: executable)
        }
        let version = versionResult.output.split(whereSeparator: \.isNewline).first
            .map { String($0).trimmingCharacters(in: .whitespaces) }
        switch backend {
        case .claude:
            let auth = await CLIProcess.run(
                executable: executable, arguments: ["auth", "status", "--json"],
                workspace: workspace, environment: environment)
            guard auth.status == 0, loggedIn(inStatusJSON: auth.output) else {
                return BackendStatus(
                    phase: .signInRequired, version: version, executable: executable)
            }
            // No prompt follows the request, so the CLI answers and exits without calling a model.
            let catalog = await CLIProcess.run(
                executable: executable,
                arguments: [
                    "-p", "--input-format", "stream-json", "--output-format", "stream-json",
                    "--verbose", "--no-session-persistence", "--strict-mcp-config",
                    "--mcp-config", #"{"mcpServers":{}}"#
                ],
                workspace: workspace, environment: environment,
                input: Data(claudeInitializeRequest.utf8), timeout: .seconds(30))
            var models = claudeCatalog(catalog.output)
            if models.isEmpty {
                models = [
                    BackendModel(id: "sonnet", name: "Claude Sonnet"),
                    BackendModel(id: "opus", name: "Claude Opus"),
                    BackendModel(id: "haiku", name: "Claude Haiku")
                ]
            }
            return BackendStatus(
                phase: .ready, version: version, executable: executable, models: models)
        case .codex:
            let login = await CLIProcess.run(
                executable: executable, arguments: ["login", "status"], workspace: workspace,
                environment: environment)
            let text = (login.output + login.error).lowercased()
            let signedIn = login.status == 0 && !text.contains("not logged in")
            return BackendStatus(
                phase: signedIn ? .ready : .signInRequired, version: version,
                executable: executable)
        }
    }

    nonisolated private static func loggedIn(inStatusJSON output: String) -> Bool {
        guard let start = output.firstIndex(of: "{"),
            let object = try? JSONSerialization.jsonObject(with: Data(output[start...].utf8))
                as? [String: Any]
        else { return false }
        return object["loggedIn"] as? Bool == true
    }

    /// The CLI's own picker, one row per resolved model: `default` only restates another entry.
    nonisolated private static func claudeCatalog(_ output: String) -> [BackendModel] {
        for line in output.split(whereSeparator: \.isNewline) {
            guard
                let object = try? JSONSerialization.jsonObject(with: Data(line.utf8))
                    as? [String: Any],
                object["type"] as? String == "control_response",
                let response = object["response"] as? [String: Any],
                let payload = response["response"] as? [String: Any],
                let entries = payload["models"] as? [[String: Any]]
            else { continue }
            var models: [BackendModel] = []
            var resolved = Set<String>()
            for entry in entries {
                guard let id = entry["value"] as? String, !id.isEmpty, id != "default" else {
                    continue
                }
                let target = entry["resolvedModel"] as? String ?? id
                guard resolved.insert(target).inserted else { continue }
                let name = entry["displayName"] as? String ?? id
                models.append(
                    BackendModel(id: id, name: name.hasPrefix("Claude") ? name : "Claude " + name))
            }
            return models
        }
        return []
    }
}
