import Foundation

/// Codex's app-server, spoken as JSON-RPC lines over stdio: one process, a short-lived read-only
/// thread per request, and answers streamed word by word.
@MainActor
final class CodexAppServer {
    enum ServerError: LocalizedError {
        /// The server never came up; the caller falls back to `codex exec`.
        case unavailable(String)
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .unavailable(let message), .failed(let message): return message
            }
        }
    }

    private let executable: URL
    private let workspace: URL
    private var process: Process?
    private var input: FileHandle?
    private var buffer = Data()
    private var nextID = 1
    /// Raw reply lines, parsed by the awaiting caller; `Data` crosses the continuation safely.
    private var pending: [Int: CheckedContinuation<Data, Error>] = [:]
    private var turns: [String: AIProviderStream.Continuation] = [:]
    private var turnIDs: [String: String] = [:]
    private var starting: Task<Void, Error>?
    private var idleShutdown: Task<Void, Never>?
    private(set) var models: [BackendModel] = []
    private(set) var defaultModel: String?
    /// Told when the account's model list arrives, so menus can offer it.
    var onModels: ([BackendModel]) -> Void = { _ in }

    private static let idleLimit: Duration = .seconds(300)

    /// Process-scoped, never written to the reader's config: no tools, plugins or update checks.
    private static let flags = [
        "-c", "check_for_update_on_startup=false",
        "-c", "features.apps=false",
        "-c", "features.plugins=false",
        "-c", "features.remote_plugin=false",
        "-c", "features.plugin_sharing=false",
        "-c", "features.shell_tool=false",
        "-c", "features.unified_exec=false",
        "-c", "features.browser_use=false",
        "-c", "features.in_app_browser=false",
        "-c", "features.computer_use=false",
        "-c", "features.image_generation=false",
        "-c", "features.multi_agent=false",
        "-c", "features.hooks=false",
        "-c", "memories.use_memories=false"
    ]

    init(executable: URL, workspace: URL) {
        self.executable = executable
        self.workspace = workspace
    }

    // MARK: - Lifecycle

    func ensureStarted() async throws {
        if process?.isRunning == true { return }
        if let starting {
            try await starting.value
            return
        }
        let task = Task { try await self.launch() }
        starting = task
        defer { starting = nil }
        try await task.value
    }

    private func launch() async throws {
        do {
            try PrivateWorkspace.prepare(workspace)
        } catch {
            throw ServerError.unavailable("Comet 42 could not prepare its private AI workspace.")
        }
        let process = Process()
        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()
        process.executableURL = executable
        process.arguments = Self.flags + ["app-server"]
        process.currentDirectoryURL = workspace
        process.environment = ExecutableLocator.environment(running: executable)
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr
        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            Task { @MainActor in self?.consume(data) }
        }
        // Drained so a chatty server can never block on a full pipe.
        stderr.fileHandleForReading.readabilityHandler = { handle in _ = handle.availableData }
        process.terminationHandler = { [weak self] _ in
            Task { @MainActor in self?.cleanUp(reason: "Codex stopped unexpectedly.") }
        }
        do {
            try process.run()
        } catch {
            throw ServerError.unavailable("Codex could not start: \(error.localizedDescription)")
        }
        // A server that exits before reading must fail the write, not SIGPIPE the app.
        _ = fcntl(stdin.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
        self.process = process
        input = stdin.fileHandleForWriting
        do {
            let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            _ = try await request(
                "initialize",
                [
                    "clientInfo": ["name": "comet-42", "title": "Comet 42", "version": version ?? "dev"],
                    "capabilities": ["experimentalApi": false]
                ], timeout: .seconds(20))
            try send(["method": "initialized", "params": [String: Any]()])
        } catch {
            stop()
            throw ServerError.unavailable("Codex app-server did not start: \(error.localizedDescription)")
        }
        await loadModels()
    }

    func stop() {
        idleShutdown?.cancel()
        if process?.isRunning == true { process?.terminate() }
        cleanUp(reason: "Codex was stopped.")
    }

    private func cleanUp(reason: String) {
        process = nil
        input = nil
        buffer.removeAll()
        let waiting = pending
        pending.removeAll()
        waiting.values.forEach { $0.resume(throwing: ServerError.failed(reason)) }
        let streams = turns
        turns.removeAll()
        turnIDs.removeAll()
        streams.values.forEach { $0.finish(throwing: AIProviderError.responseFailed(reason)) }
    }

    /// Kept warm between requests, and shut down once nothing has used it for a while.
    private func scheduleIdleShutdown(after delay: Duration = idleLimit) {
        idleShutdown?.cancel()
        idleShutdown = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self, self.turns.isEmpty else { return }
            self.stop()
        }
    }

    /// The account's models, for the model menus; the server is then left to idle out quickly.
    func refreshModels() async {
        do {
            try await ensureStarted()
            if turns.isEmpty { scheduleIdleShutdown(after: .seconds(30)) }
        } catch {
            models = []
        }
    }

    private func loadModels() async {
        guard let response = try? await request("model/list", ["includeHidden": false, "limit": 100])
        else { return }
        let entries = response["data"] as? [[String: Any]] ?? []
        models = entries.compactMap { entry in
            guard let id = entry["model"] as? String, !id.isEmpty else { return nil }
            return BackendModel(id: id, name: entry["displayName"] as? String ?? id)
        }
        defaultModel = entries.first { $0["isDefault"] as? Bool == true }?["model"] as? String
        onModels(models)
    }

    // MARK: - Requests

    @discardableResult
    func request(
        _ method: String, _ params: [String: Any], timeout: Duration = .seconds(60)
    ) async throws -> [String: Any] {
        let id = nextID
        nextID += 1
        try send(["id": id, "method": method, "params": params])
        let line: Data = try await withCheckedThrowingContinuation { continuation in
            pending[id] = continuation
            Task { [weak self] in
                try? await Task.sleep(for: timeout)
                self?.expire(id, method: method)
            }
        }
        guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else {
            throw ServerError.failed("Codex sent an unreadable reply.")
        }
        if let error = object["error"] as? [String: Any] {
            throw ServerError.failed(error["message"] as? String ?? "Codex returned an error.")
        }
        return object["result"] as? [String: Any] ?? [:]
    }

    private func expire(_ id: Int, method: String) {
        pending.removeValue(forKey: id)?.resume(
            throwing: ServerError.failed("Codex didn’t answer \(method) in time."))
    }

    private func send(_ object: [String: Any]) throws {
        guard let input else { throw ServerError.failed("Codex isn’t running.") }
        var data = try JSONSerialization.data(withJSONObject: object)
        data.append(0x0A)
        try input.write(contentsOf: data)
    }

    private func consume(_ data: Data) {
        buffer.append(data)
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = Data(buffer[buffer.startIndex..<newline])
            buffer.removeSubrange(buffer.startIndex...newline)
            guard !line.isEmpty,
                let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any]
            else { continue }
            if let method = object["method"] as? String {
                if let id = object["id"] {
                    decline(id: id)
                } else {
                    notify(method, object["params"] as? [String: Any] ?? [:])
                }
            } else if let id = (object["id"] as? NSNumber)?.intValue {
                pending.removeValue(forKey: id)?.resume(returning: line)
            }
        }
    }

    /// Approvals, elicitations and anything else the server asks: Comet 42 grants nothing.
    private func decline(id: Any) {
        try? send([
            "id": id,
            "error": ["code": -32_601, "message": "Comet 42 does not allow this request."]
        ])
    }

    private func notify(_ method: String, _ params: [String: Any]) {
        guard let thread = params["threadId"] as? String, let continuation = turns[thread] else {
            return
        }
        switch method {
        case "item/agentMessage/delta":
            if let delta = params["delta"] as? String, !delta.isEmpty { continuation.yield(.text(delta)) }
        case "item/started":
            if (params["item"] as? [String: Any])?["type"] as? String == "reasoning" {
                continuation.yield(.thinking)
            }
        case "item/reasoning/summaryTextDelta":
            continuation.yield(.thinking)
        case "turn/started":
            if let id = (params["turn"] as? [String: Any])?["id"] as? String { turnIDs[thread] = id }
        case "turn/completed":
            let turn = params["turn"] as? [String: Any]
            switch turn?["status"] as? String {
            case "completed":
                continuation.finish()
            case "failed":
                let message = (turn?["error"] as? [String: Any])?["message"] as? String
                continuation.finish(
                    throwing: AIProviderError.responseFailed(message ?? "Codex could not finish the response."))
            default:
                continuation.finish(throwing: AIProviderError.responseFailed("The response was interrupted."))
            }
            endTurn(thread)
        case "error":
            guard params["willRetry"] as? Bool != true else { return }
            let message = (params["error"] as? [String: Any])?["message"] as? String
            continuation.finish(throwing: AIProviderError.responseFailed(message ?? "Codex returned an error."))
            endTurn(thread)
        default:
            break
        }
    }

    // MARK: - Turns

    func run(
        _ request: AIRequest, model: String, effort: String?,
        continuation: AIProviderStream.Continuation
    ) async {
        idleShutdown?.cancel()
        do {
            try await ensureStarted()
        } catch {
            continuation.finish(throwing: error)
            return
        }
        guard let lastIndex = request.messages.lastIndex(where: { $0.role == .user }) else {
            continuation.finish(throwing: AIProviderError.unavailable("There is no question to send."))
            return
        }
        let last = request.messages[lastIndex]
        let chosen = model.isEmpty ? (defaultModel ?? "") : model
        do {
            var threadParams: [String: Any] = [
                "cwd": workspace.path,
                "approvalPolicy": "never",
                "sandbox": "read-only",
                "ephemeral": true,
                "developerInstructions": TranscriptPrompt.safetyInstructions + "\n\n" + request.instructions
            ]
            if !chosen.isEmpty { threadParams["model"] = chosen }
            let thread = try await self.request("thread/start", threadParams)
            guard let threadID = (thread["thread"] as? [String: Any])?["id"] as? String else {
                throw ServerError.failed("Codex returned no thread.")
            }
            turns[threadID] = continuation
            continuation.onTermination = { [weak self] reason in
                guard case .cancelled = reason else { return }
                Task { @MainActor in self?.interrupt(threadID) }
            }
            let history = request.messages[..<lastIndex]
            if !history.isEmpty {
                _ = try await self.request(
                    "thread/inject_items", ["threadId": threadID, "items": history.map(Self.historyItem)])
            }
            var turn: [String: Any] = [
                "threadId": threadID,
                "approvalPolicy": "never",
                "sandboxPolicy": ["type": "readOnly", "networkAccess": false],
                "input": Self.input(for: last)
            ]
            if !chosen.isEmpty { turn["model"] = chosen }
            if let effort { turn["effort"] = effort }
            let started = try await self.request("turn/start", turn)
            if let id = (started["turn"] as? [String: Any])?["id"] as? String { turnIDs[threadID] = id }
        } catch {
            continuation.finish(throwing: AIProviderError.responseFailed(error.localizedDescription))
            if turns.isEmpty { scheduleIdleShutdown() }
        }
    }

    private func interrupt(_ thread: String) {
        if let turnID = turnIDs[thread] {
            Task { _ = try? await self.request("turn/interrupt", ["threadId": thread, "turnId": turnID]) }
        }
        endTurn(thread)
    }

    private func endTurn(_ thread: String) {
        turns[thread] = nil
        turnIDs[thread] = nil
        if turns.isEmpty { scheduleIdleShutdown() }
    }

    private static func input(for message: AIMessage) -> [[String: Any]] {
        var input: [[String: Any]] = []
        if !message.text.isEmpty { input.append(["type": "text", "text": message.text]) }
        input += message.images.map { ["type": "image", "url": $0.dataURL] }
        return input
    }

    private static func historyItem(_ message: AIMessage) -> [String: Any] {
        let isUser = message.role == .user
        var content: [[String: Any]] = []
        if !message.text.isEmpty {
            content.append(["type": isUser ? "input_text" : "output_text", "text": message.text])
        }
        content += message.images.map { ["type": "input_image", "image_url": $0.dataURL] }
        return ["type": "message", "role": isUser ? "user" : "assistant", "content": content]
    }
}

/// Streams through the app-server, and falls back to `codex exec` if the server never starts.
nonisolated struct CodexAppServerProvider: AIProvider {
    let server: CodexAppServer
    let fallback: CodexCLIProvider
    let model: String
    let effort: String?
    let onFallback: @MainActor @Sendable () -> Void

    func stream(_ request: AIRequest) -> AIProviderStream {
        let primary = AIProviderStream { continuation in
            Task { @MainActor in
                await server.run(request, model: model, effort: effort, continuation: continuation)
            }
        }
        return AIProviderStream { continuation in
            let task = Task {
                var yielded = false
                do {
                    for try await event in primary {
                        yielded = true
                        continuation.yield(event)
                    }
                    continuation.finish()
                } catch CodexAppServer.ServerError.unavailable where !yielded {
                    await onFallback()
                    do {
                        for try await event in fallback.stream(request) { continuation.yield(event) }
                        continuation.finish()
                    } catch {
                        continuation.finish(throwing: error)
                    }
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
