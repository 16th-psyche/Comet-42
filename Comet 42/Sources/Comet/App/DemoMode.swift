import AppKit
import SwiftUI

/// `Comet --demo <rewrite|chat|context|settings> [--light]`: shows one sample screen for the
/// README's screenshots. It saves nothing, registers no hotkey and uses a throwaway presets folder,
/// so a running copy of the app and the reader's data are untouched. Prints `WINDOW <number>`.
enum DemoMode {
    static func run() {
        let app = NSApplication.shared
        let delegate = DemoDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.appearance = NSAppearance(
            named: CommandLine.arguments.contains("--light") ? .aqua : .darkAqua)
        app.run()
        _ = delegate
    }
}

private final class DemoDelegate: NSObject, NSApplicationDelegate {
    private var controller: CometController!
    private var panel: CometPanelController!
    private var settingsWindow: NSWindow?

    private static let shots = ["rewrite", "chat", "context", "settings"]

    func applicationDidFinishLaunching(_ notification: Notification) {
        let shot = CommandLine.arguments.first { Self.shots.contains($0) } ?? "rewrite"
        let support = FileManager.default.temporaryDirectory.appending(path: "Comet-demo")
        try? FileManager.default.removeItem(at: support)
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)

        let settings = AppSettings()
        settings.persists = false
        settings.textScale = 1
        settings.hidesOnFocusLoss = false
        settings.remembersPanelPosition = false
        settings.panelWidth = 660
        settings.panelMaxHeight = 600
        settings.chatModel = ModelChoice(backend: .claude, model: "sonnet")

        let backends = AIBackends(supportDirectory: support)
        backends.refresh()
        controller = CometController(
            settings: settings, presets: PresetStore(supportDirectory: support),
            backends: backends, watcher: ClipboardWatcher(), hud: HUDController())
        panel = CometPanelController(controller: controller)
        controller.panel = panel

        let session = controller.session
        session.sourceApp =
            NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == "com.apple.TextEdit" }
            ?? NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == "com.apple.Notes" }

        switch shot {
        case "chat": loadChat(session)
        case "context": loadContext(session)
        case "settings": break
        default: loadRewrite(session)
        }

        Task { @MainActor in
            // Long enough for the CLI catalog to name the model in the footer.
            try? await Task.sleep(for: .seconds(4))
            if shot == "settings" {
                self.showSettings(settings: settings)
                try? await Task.sleep(for: .seconds(1.5))
                print("WINDOW \(self.settingsWindow?.windowNumber ?? 0)")
            } else {
                self.panel.show()
                try? await Task.sleep(for: .seconds(0.8))
                // Typed after focus, so the field shows a caret rather than a selected draft.
                if shot == "context" {
                    self.controller.session.draft = "Turn this and the chart into a short status update"
                }
                try? await Task.sleep(for: .seconds(1.2))
                print("WINDOW \(self.panel.windowNumber)")
            }
            fflush(stdout)
        }
    }

    private func loadRewrite(_ session: CometSession) {
        let original =
            "hey team i has went thru the report its ok but numbers in q3 looks off, can someone check by friday"
        session.turns = [
            ChatTurn(
                role: .user, display: "Fix Spelling and Grammar", prompt: "", contextPreview: original,
                presetName: "Fix Spelling and Grammar", presetSymbol: "textformat.abc"),
            ChatTurn(
                role: .assistant,
                display:
                    "Hey team, I went through the report. It's okay, but the numbers in Q3 look off. Can someone check by Friday?",
                prompt: "", presetName: "Fix Spelling and Grammar", original: original, showsDiff: true)
        ]
        controller.loadDemo(selection: original)
    }

    private func loadChat(_ session: CometSession) {
        let update = """
            Quarterly update: revenue grew 12% to $4.2M, churn fell to 3.1%, and the team shipped \
            the new onboarding flow. Hiring is behind plan with 2 of 5 roles filled. Risks: the \
            vendor contract renewal in November and a possible delay in the EU launch.
            """
        session.turns = [
            ChatTurn(
                role: .user, display: "What are the main risks here, and what should we do first?",
                prompt: "", contextPreview: update),
            ChatTurn(
                role: .assistant,
                display: """
                    **Main risks**
                    1. **Vendor contract renewal (November)**: it's about a month away, and a lapse or a price hike could disrupt operations.
                    2. **EU launch delay**: the compliance review could push it back and slow growth.
                    3. **Hiring gap (2 of 5 filled)**: this threatens next quarter's goals, since enterprise sales and the mobile beta both need people.

                    **What to do first**
                    Start the vendor renewal now. It has a hard November deadline, it's the closest risk, and you can negotiate from a stronger position if you begin early.
                    """,
                prompt: "")
        ]
        controller.loadDemo(selection: update)
    }

    private func loadContext(_ session: CometSession) {
        session.texts = [
            StagedText(
                kind: .selection,
                text: "Notes from standup: design signed off on onboarding v2, QA found 3 blockers in checkout, EU legal review is next week.")
        ]
        if let chart = ClipboardImage.stage(Self.chartImage(), name: "Screenshot") {
            session.images = [chart]
        }
        controller.loadDemo(selection: session.texts[0].text)
    }

    private func showSettings(settings: AppSettings) {
        controller.settingsTab = "presets"
        let view = SettingsView(controller: controller, hotKeys: HotKeyCenter(), applyHotKey: { true })
        let window = NSWindow(contentViewController: NSHostingController(rootView: view))
        window.title = "Comet 42 Settings"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.toolbar = NSToolbar(identifier: "CometDemoSettings")
        window.toolbarStyle = .unified
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.setContentSize(NSSize(width: 900, height: 600))
        window.center()
        settingsWindow = window
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    /// A small bar chart, standing in for a copied screenshot.
    private static func chartImage() -> Data {
        let size = NSSize(width: 320, height: 200)
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.white.setFill()
            rect.fill()
            let colors: [NSColor] = [.systemBlue, .systemPurple, .systemPink, .systemTeal]
            for (index, height) in [90.0, 140.0, 110.0, 170.0].enumerated() {
                colors[index].setFill()
                NSBezierPath(
                    roundedRect: NSRect(x: 30 + Double(index) * 70, y: 15, width: 46, height: height),
                    xRadius: 6, yRadius: 6
                ).fill()
            }
            return true
        }
        return image.tiffRepresentation ?? Data()
    }
}
