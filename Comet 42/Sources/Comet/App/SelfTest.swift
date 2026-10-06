import AppKit

/// `Comet --selftest [codex]`: drives the real CLI providers from a terminal, no UI involved.
enum SelfTest {
    /// `Comet --selftest history`: the history store's save, cap, reload and clear, offline.
    static func historyCheck() -> Bool {
        let folder = FileManager.default.temporaryDirectory.appending(path: "Comet-history-check")
        try? FileManager.default.removeItem(at: folder)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var failures: [String] = []
        func expect(_ ok: Bool, _ what: String) { if !ok { failures.append(what) } }

        let settings = AppSettings()
        settings.persists = false
        let store = ChatHistoryStore(supportDirectory: folder)
        expect(store.chats.isEmpty, "starts empty")
        let turns = [
            ChatTurn(role: .user, display: "First question", prompt: "p"),
            ChatTurn(role: .assistant, display: "An answer", prompt: "")
        ]
        let id = UUID()
        store.save(id: id, turns: turns)
        store.save(id: id, turns: turns + [ChatTurn(role: .user, display: "More", prompt: "p")])
        expect(store.chats.count == 1, "saving the same chat twice keeps one entry")
        store.save(id: UUID(), turns: [ChatTurn(role: .user, display: "No answer yet", prompt: "")])
        expect(store.chats.count == 1, "a chat without an answer is not saved")
        for index in 0..<60 {
            store.save(id: UUID(), turns: [
                ChatTurn(role: .user, display: "Q\(index)", prompt: ""),
                ChatTurn(role: .assistant, display: "A", prompt: "")
            ])
        }
        expect(store.chats.count == ChatHistoryStore.limit, "capped at \(ChatHistoryStore.limit)")
        expect(store.chats.first?.title == "Q59", "newest first")
        let reloaded = ChatHistoryStore(supportDirectory: folder)
        expect(reloaded.chats.count == ChatHistoryStore.limit, "reloads from disk")
        reloaded.clear()
        expect(!FileManager.default.fileExists(atPath: folder.appending(path: "history.json").path),
               "clear deletes the file")
        print(failures.isEmpty ? "history: all checks passed" : "history FAILED: " + failures.joined(separator: "; "))
        try? FileManager.default.removeItem(at: folder)
        return failures.isEmpty
    }

    static func run() {
        if CommandLine.arguments.contains("history") {
            exit(historyCheck() ? 0 : 1)
        }
        let backend: AIBackend = CommandLine.arguments.contains("codex") ? .codex : .claude
        Task {
            let support = FileManager.default.temporaryDirectory.appending(path: "Comet-selftest")
            try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
            let backends = AIBackends(supportDirectory: support)
            backends.refresh()
            while case .checking = backends.status(backend).phase {
                try? await Task.sleep(for: .milliseconds(100))
            }
            let status = backends.status(backend)
            print("\(backend.title): \(status.summary) — \(backends.models(for: backend).map(\.id))")
            let model = backend == .claude ? "haiku" : ""
            do {
                let provider = try backends.provider(
                    for: ModelChoice(backend: backend, model: model), effort: nil)
                for preset in Preset.builtIns.prefix(6) {
                    try await ask(
                        provider, preset.name, preset: preset,
                        message: PresetPrompt.message(
                            selection: "hey team i has went thru the report its ok but numbers in q3 looks off, "
                                + "can someone check by friday", hasImages: false))
                }
                let image = drawImage(text: "COMET 42")
                try await ask(
                    provider, "Image", preset: nil,
                    message: "What text is in this image? Reply with the text only.", images: [image])
                exit(0)
            } catch {
                print("FAILED: \(error.localizedDescription)")
                exit(1)
            }
        }
        RunLoop.main.run()
    }

    private static func ask(
        _ provider: any AIProvider, _ label: String, preset: Preset?, message: String,
        images: [AIImage] = []
    ) async throws {
        let request = AIRequest(
            instructions: preset.map(PresetPrompt.instructions(for:))
                ?? CometController.chatInstructions,
            messages: [AIMessage(role: .user, text: message, images: images)])
        var text = ""
        var deltas = 0
        for try await event in provider.stream(request) {
            if case .text(let delta) = event {
                text += delta
                deltas += 1
            }
        }
        print("[\(label)] \(deltas) deltas → \(text.trimmingCharacters(in: .whitespacesAndNewlines))")
    }

    private static func drawImage(text: String) -> AIImage {
        let size = NSSize(width: 360, height: 120)
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.white.setFill()
            rect.fill()
            (text as NSString).draw(
                at: NSPoint(x: 20, y: 40),
                withAttributes: [.font: NSFont.boldSystemFont(ofSize: 40), .foregroundColor: NSColor.black])
            return true
        }
        let tiff = image.tiffRepresentation!
        return ClipboardImage.stage(tiff, name: "test")!.image
    }
}
