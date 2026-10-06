import Foundation

nonisolated struct ClaudeCLIProvider: AIProvider {
    let executable: URL
    let model: String
    let effort: String?
    let workspace: URL

    func stream(_ request: AIRequest) -> AIProviderStream {
        let prompt = TranscriptPrompt.render(request, includingSafety: false)
        guard let line = Self.userMessage(prompt, images: request.allImages) else {
            return AIProviderStream {
                $0.finish(throwing: AIProviderError.unavailable("Could not frame the request."))
            }
        }
        let lines = CLIProcess.lines(
            executable: executable, arguments: arguments, workspace: workspace,
            environment: ExecutableLocator.environment(
                running: executable, adding: ["CLAUDE_CODE_SKIP_PROMPT_HISTORY": "1"]),
            input: line)
        return AIProviderStream { continuation in
            let task = Task.detached {
                do {
                    var completed = false
                    for try await raw in lines {
                        switch Self.decode(raw) {
                        case .events(let events): events.forEach { continuation.yield($0) }
                        case .failed(let message): throw AIProviderError.responseFailed(message)
                        case .completed: completed = true
                        case .ignored: break
                        }
                    }
                    guard completed else {
                        throw AIProviderError.responseFailed(
                            "Claude closed before the response completed.")
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
            "-p",
            "--input-format", "stream-json",
            "--output-format", "stream-json",
            "--verbose",
            "--include-partial-messages",
            "--no-session-persistence",
            "--disable-slash-commands",
            "--tools", "",
            // `--bare` is not among these: it refuses the OAuth sign-in this whole route reuses.
            "--no-chrome",
            "--system-prompt", TranscriptPrompt.safetyInstructions,
            "--disallowedTools", "*",
            "--max-turns", "1",
            "--strict-mcp-config", "--mcp-config", #"{"mcpServers":{}}"#
        ]
        if !model.isEmpty { result += ["--model", model] }
        if let effort, !effort.isEmpty { result += ["--effort", effort] }
        return result
    }

    /// Framed as JSON, so a picture rides beside the text as a content block.
    static func userMessage(_ text: String, images: [AIImage]) -> Data? {
        let pictures: [[String: Any]] = images.map { image in
            [
                "type": "image",
                "source": [
                    "type": "base64", "media_type": image.mimeType,
                    "data": image.data.base64EncodedString()
                ]
            ]
        }
        let content: Any = images.isEmpty ? text : pictures + [["type": "text", "text": text]]
        var line = try? JSONSerialization.data(
            withJSONObject: ["type": "user", "message": ["role": "user", "content": content]])
        line?.append(0x0A)
        return line
    }

    enum Frame: Equatable {
        case events([AIStreamEvent])
        case failed(String)
        case completed
        case ignored
    }

    static func decode(_ line: String) -> Frame {
        guard let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
            let type = object["type"] as? String
        else { return .ignored }
        if type == "stream_event", let event = object["event"] as? [String: Any],
            let delta = event["delta"] as? [String: Any]
        {
            switch delta["type"] as? String {
            case "text_delta":
                guard let text = delta["text"] as? String, !text.isEmpty else { return .ignored }
                return .events([.text(text)])
            case "thinking_delta":
                return .events([.thinking])
            default:
                return .ignored
            }
        }
        guard type == "result" else { return .ignored }
        if object["is_error"] as? Bool == true {
            let message = object["result"] as? String
            return .failed(
                (message?.isEmpty == false ? message : nil) ?? "Claude could not finish the response.")
        }
        return .completed
    }
}
