import Foundation

/// An attached picture, already encoded for the wire.
nonisolated struct AIImage: Equatable, Hashable, Sendable {
    let data: Data
    let mimeType: String

    var dataURL: String { "data:\(mimeType);base64,\(data.base64EncodedString())" }
}

nonisolated struct AIMessage: Equatable, Sendable {
    enum Role: String, Equatable, Sendable {
        case user
        case assistant
    }

    let role: Role
    let text: String
    let images: [AIImage]

    init(role: Role, text: String, images: [AIImage] = []) {
        self.role = role
        self.text = text
        self.images = images
    }
}

nonisolated struct AIRequest: Equatable, Sendable {
    let instructions: String
    let messages: [AIMessage]

    /// Every CLI turn starts with no memory, so pictures from earlier turns ride the newest one.
    var allImages: [AIImage] { messages.flatMap(\.images) }
}

nonisolated enum AIStreamEvent: Equatable, Sendable {
    case text(String)
    case thinking
}

nonisolated enum AIProviderError: LocalizedError, Sendable {
    case unavailable(String)
    case responseFailed(String)

    var errorDescription: String? {
        switch self {
        case .unavailable(let message), .responseFailed(let message): return message
        }
    }
}

typealias AIProviderStream = AsyncThrowingStream<AIStreamEvent, Error>

/// Never main-bound: a stream does its own IO and decoding, and hands the main actor only events.
nonisolated protocol AIProvider: Sendable {
    func stream(_ request: AIRequest) -> AIProviderStream
}

nonisolated enum AIBackend: String, Codable, CaseIterable, Identifiable, Sendable {
    case claude
    case codex

    var id: String { rawValue }

    var title: String {
        switch self {
        case .claude: return "Claude"
        case .codex: return "Codex"
        }
    }

    var command: String { rawValue }

    var extraExecutablePaths: [String] {
        switch self {
        case .claude: return [".claude/local/claude"]
        case .codex: return []
        }
    }

    var signInCommand: String {
        switch self {
        case .claude: return "claude auth login"
        case .codex: return "codex login"
        }
    }

    var installHint: String {
        switch self {
        case .claude: return "curl -fsSL https://claude.ai/install.sh | bash"
        case .codex: return "npm i -g @openai/codex"
        }
    }
}

/// Which CLI answers and with what model; an empty model leaves the choice to the CLI.
nonisolated struct ModelChoice: Codable, Hashable, Sendable {
    var backend: AIBackend
    var model: String

    static let `default` = ModelChoice(backend: .claude, model: "sonnet")
}

/// The shared transcript framing: a fresh CLI process sees the whole chat as one prompt.
nonisolated enum TranscriptPrompt {
    static let safetyInstructions = """
        You are generating text inside Comet 42, a small macOS helper. Do not invoke tools, read \
        files, run commands, inspect the environment, access external resources, or modify \
        anything. Use only the conversation and instructions in this request.
        """

    static func render(_ request: AIRequest, includingSafety: Bool) -> String {
        var sections: [String] = []
        if includingSafety { sections.append(safetyInstructions) }
        let instructions = request.instructions.trimmingCharacters(in: .whitespacesAndNewlines)
        if !instructions.isEmpty { sections.append("Instructions:\n" + instructions) }
        // A single question needs no transcript labels; they only matter once there is history.
        if request.messages.count == 1, let only = request.messages.first {
            sections.append(only.text)
            return sections.joined(separator: "\n\n")
        }
        for message in request.messages {
            let text = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            sections.append((message.role == .user ? "User" : "Assistant") + ":\n" + text)
        }
        return sections.joined(separator: "\n\n")
    }
}
