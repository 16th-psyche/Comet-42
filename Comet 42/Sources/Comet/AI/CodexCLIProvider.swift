import Foundation

/// `codex exec --json`: one ephemeral, read-only turn per request; the prompt arrives on stdin.
nonisolated struct CodexCLIProvider: AIProvider {
    let executable: URL
    let model: String
    let effort: String?
    let workspace: URL

    func stream(_ request: AIRequest) -> AIProviderStream {
        let prompt = TranscriptPrompt.render(request, includingSafety: true)
        let workspace = workspace
        let executable = executable
        let baseArguments = arguments
        return AIProviderStream { continuation in
            let task = Task.detached {
                var imageFiles: [URL] = []
                defer { imageFiles.forEach { try? FileManager.default.removeItem(at: $0) } }
                do {
                    try PrivateWorkspace.prepare(workspace)
                    var arguments = baseArguments
                    for image in request.allImages {
                        let url = workspace.appending(path: "comet-image-\(UUID().uuidString).png")
                        try image.data.write(to: url, options: .atomic)
                        imageFiles.append(url)
                        arguments += ["--image", url.path]
                    }
                    arguments.append("-")
                    let lines = CLIProcess.lines(
                        executable: executable, arguments: arguments, workspace: workspace,
                        environment: ExecutableLocator.environment(running: executable),
                        input: Data(prompt.utf8))
                    var decoder = Decoder()
                    for try await raw in lines {
                        for event in try decoder.feed(raw) { continuation.yield(event) }
                        if decoder.completed { break }
                    }
                    guard decoder.completed || decoder.emittedText else {
                        throw AIProviderError.responseFailed(
                            "Codex closed before the response completed.")
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private var arguments: [String] {
        var result = [
            "exec", "--json", "--skip-git-repo-check", "--ephemeral", "--sandbox", "read-only",
            "--color", "never"
        ]
        if !model.isEmpty { result += ["--model", model] }
        if let effort, !effort.isEmpty { result += ["-c", "model_reasoning_effort=\"\(effort)\""] }
        return result
    }

    /// Agent messages arrive whole or as growing updates; only the unseen suffix is yielded.
    struct Decoder {
        private var emitted: [String: Int] = [:]
        private(set) var completed = false
        private(set) var emittedText = false

        mutating func feed(_ line: String) throws -> [AIStreamEvent] {
            guard
                let object = try? JSONSerialization.jsonObject(with: Data(line.utf8))
                    as? [String: Any],
                let type = object["type"] as? String
            else { return [] }
            switch type {
            case "item.started", "item.updated", "item.completed":
                guard let item = object["item"] as? [String: Any] else { return [] }
                switch item["type"] as? String {
                case "agent_message":
                    let id = item["id"] as? String ?? ""
                    let text = item["text"] as? String ?? ""
                    let seen = emitted[id] ?? 0
                    guard text.count > seen else { return [] }
                    emitted[id] = text.count
                    // A second message starts a new paragraph rather than running into the first.
                    let separator = seen == 0 && emittedText ? "\n\n" : ""
                    emittedText = true
                    return [.text(separator + String(text.dropFirst(seen)))]
                case "reasoning":
                    return [.thinking]
                default:
                    return []
                }
            case "turn.completed":
                completed = true
                return []
            case "turn.failed":
                let error = object["error"] as? [String: Any]
                throw AIProviderError.responseFailed(
                    error?["message"] as? String ?? "Codex could not finish the response.")
            case "error":
                throw AIProviderError.responseFailed(
                    object["message"] as? String ?? "Codex reported an error.")
            default:
                return []
            }
        }
    }
}

nonisolated enum PrivateWorkspace {
    static func prepare(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
    }
}
