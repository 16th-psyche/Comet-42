import Foundation
import Observation

/// One saved turn: the text only. Pictures are never written to disk.
nonisolated struct SavedTurn: Codable, Equatable, Sendable {
    var isUser: Bool
    var display: String
    var prompt: String
    var presetName: String?
    var presetSymbol: String?
    var contextPreview: String?
}

nonisolated struct SavedChat: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    var title: String
    var date: Date
    var turns: [SavedTurn]
}

/// Recent chats on this Mac only, written only while the reader has history turned on.
@Observable
final class ChatHistoryStore {
    private(set) var chats: [SavedChat] = []
    @ObservationIgnored private let file: URL

    static let limit = 50

    init(supportDirectory: URL) {
        file = supportDirectory.appending(path: "history.json")
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let data = try? Data(contentsOf: file),
            let saved = try? decoder.decode([SavedChat].self, from: data)
        {
            chats = saved
        }
    }

    /// Newest first; saving a chat again moves it to the top rather than duplicating it.
    func save(id: UUID, turns: [ChatTurn]) {
        let saved = turns.compactMap { turn -> SavedTurn? in
            guard !turn.display.isEmpty || turn.role == .user, turn.error == nil else { return nil }
            return SavedTurn(
                isUser: turn.role == .user, display: turn.display, prompt: turn.prompt,
                presetName: turn.presetName, presetSymbol: turn.presetSymbol,
                contextPreview: turn.contextPreview)
        }
        guard saved.contains(where: { !$0.isUser }) else { return }
        let first = saved.first { $0.isUser }?.display ?? "Chat"
        let title = first.count > 60 ? String(first.prefix(59)) + "…" : first
        chats.removeAll { $0.id == id }
        chats.insert(SavedChat(id: id, title: title, date: Date(), turns: saved), at: 0)
        if chats.count > Self.limit { chats.removeLast(chats.count - Self.limit) }
        write()
    }

    func delete(id: UUID) {
        chats.removeAll { $0.id == id }
        write()
    }

    /// Removes the file itself, not just its contents.
    func clear() {
        chats = []
        try? FileManager.default.removeItem(at: file)
    }

    private func write() {
        guard !chats.isEmpty else {
            try? FileManager.default.removeItem(at: file)
            return
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(chats) else { return }
        try? data.write(to: file, options: [.atomic, .completeFileProtection])
    }
}

extension SavedTurn {
    var chatTurn: ChatTurn {
        ChatTurn(
            role: isUser ? .user : .assistant, display: display, prompt: prompt,
            contextPreview: contextPreview, presetName: presetName, presetSymbol: presetSymbol)
    }
}
