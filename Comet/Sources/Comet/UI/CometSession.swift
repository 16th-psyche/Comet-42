import AppKit
import Observation

struct ChatTurn: Identifiable, Equatable {
    enum Role: Equatable {
        case user
        case assistant
    }

    let id = UUID()
    let role: Role
    /// What the transcript shows; for a user turn this omits the context block the prompt carries.
    var display: String
    /// What the model is sent for this turn.
    var prompt: String
    var images: [AIImage] = []
    var contextPreview: String?
    var presetName: String?
    var presetSymbol: String?
    var isStreaming = false
    var isThinking = false
    var error: String?
    /// The selection a transform worked on, kept for the diff and for Replace.
    var original: String?
    var showsDiff = false
}

/// A piece of text staged beside the question: the selection, something pasted, or a file's text.
struct StagedText: Identifiable, Equatable {
    enum Kind: Equatable {
        case selection
        case pasted
        case file(String)
    }

    let id = UUID()
    let kind: Kind
    let text: String

    var title: String {
        switch kind {
        case .selection: return "Selected text"
        case .pasted: return "Pasted text"
        case .file(let name): return name
        }
    }

    var symbol: String {
        switch kind {
        case .selection: return "text.cursor"
        case .pasted: return "doc.on.clipboard"
        case .file: return "doc.text"
        }
    }

    /// The prompt's framing; a tag per kind tells the model where each piece came from.
    var promptBlock: String {
        switch kind {
        case .selection: return "<selected_text>\n\(text)\n</selected_text>"
        case .pasted: return "<pasted_text>\n\(text)\n</pasted_text>"
        case .file(let name):
            let safe = name.replacingOccurrences(of: "\"", with: "'")
            return "<file name=\"\(safe)\">\n\(text)\n</file>"
        }
    }
}

/// One Comet 42 conversation and the context it was summoned with.
@Observable
final class CometSession {
    var texts: [StagedText] = []
    var images: [StagedImage] = []
    /// A clipboard picture that was too old to attach on its own, offered as a one-click chip.
    var offeredImage: StagedImage?
    var turns: [ChatTurn] = []
    var draft = ""
    var model: ModelChoice
    var lastActivity = Date()
    @ObservationIgnored var sourceApp: NSRunningApplication?
    @ObservationIgnored var running: Task<Void, Never>?

    init(model: ModelChoice) {
        self.model = model
    }

    var isRunning: Bool { turns.last?.isStreaming == true }
    var hasContext: Bool { !texts.isEmpty || !images.isEmpty }
    var lastAnswer: ChatTurn? { turns.last { $0.role == .assistant && !$0.display.isEmpty } }
    var selection: String? { texts.first { $0.kind == .selection }?.text }

    /// Every staged text joined, which is what a preset works on.
    var combinedText: String? {
        texts.isEmpty ? nil : texts.map(\.text).joined(separator: "\n\n")
    }

    /// The whole chat as the model sees it, pictures included.
    var messages: [AIMessage] {
        turns.compactMap { turn in
            switch turn.role {
            case .user:
                return AIMessage(role: .user, text: turn.prompt, images: turn.images)
            case .assistant:
                guard !turn.display.isEmpty else { return nil }
                return AIMessage(role: .assistant, text: turn.display)
            }
        }
    }

    func setSelection(_ text: String) {
        texts.removeAll { $0.kind == .selection }
        texts.insert(StagedText(kind: .selection, text: text), at: 0)
    }

    func reset() {
        running?.cancel()
        running = nil
        texts = []
        images = []
        offeredImage = nil
        turns = []
        draft = ""
    }
}
