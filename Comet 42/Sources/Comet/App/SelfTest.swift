import AppKit

/// `Comet --selftest [codex]`: drives the real CLI providers from a terminal, no UI involved.
enum SelfTest {
    static func run() {
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
            print("\(backend.title): \(status.summary) — \(status.models.map(\.id))")
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
