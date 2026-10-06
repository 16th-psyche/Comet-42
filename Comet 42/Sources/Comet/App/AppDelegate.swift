import AppKit
import SwiftUI

@main
enum CometApp {
    static func main() {
        if CommandLine.arguments.contains("--print-default-presets") {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            print(String(decoding: try! encoder.encode(Preset.builtIns), as: UTF8.self))
            return
        }
        if CommandLine.arguments.contains("--demo") {
            DemoMode.run()
            return
        }
        if CommandLine.arguments.contains("--selftest") {
            SelfTest.run()
            return
        }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
        _ = delegate
    }
}

/// The composition root: the one owner of every long-lived object.
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let settings = AppSettings()
    private let hotKeys = HotKeyCenter()
    private let watcher = ClipboardWatcher()
    private let hud = HUDController()
    private var controller: CometController!
    private var panel: CometPanelController!
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?
    private var onboardingWindow: NSWindow?

    private static let mainHotKeyID: UInt32 = 1
    /// Preset shortcuts take ids from here up, one per preset that has a shortcut.
    private static let presetHotKeyBase: UInt32 = 100
    private var presetHotKeyIDs: [UInt32] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        let support = Self.supportDirectory()
        let backends = AIBackends(supportDirectory: support)
        backends.codexModels = settings.codexModels
        controller = CometController(
            settings: settings, presets: PresetStore(supportDirectory: support),
            backends: backends, watcher: watcher, hud: hud)
        panel = CometPanelController(controller: controller)
        controller.panel = panel
        controller.openSettings = { [weak self] in self?.showSettings() }

        installMainMenu()
        installStatusItem()
        watcher.start()
        backends.refresh()
        // Asked once here (onboarding asks instead on a first run): a prompt from the hotkey would
        // steal focus and hide the panel.
        if settings.hasCompletedOnboarding, !Permissions.isAccessibilityTrusted {
            Permissions.ensureAccessibility()
        }
        let registered = applyHotKey()
        controller.presets.onChange = { [weak self] in self?.registerPresetHotKeys() }
        registerPresetHotKeys()
        if !settings.hasCompletedOnboarding {
            showOnboarding()
        } else if !registered {
            hud.show(
                "\(settings.hotKey.displayString) is taken by another app — pick one in Settings",
                tone: .danger)
        }
    }

    @discardableResult
    private func applyHotKey() -> Bool {
        hotKeys.register(id: Self.mainHotKeyID, chord: settings.hotKey) { [weak self] in
            self?.controller.toggle()
        }
    }

    /// Re-registered whenever presets change, so a removed or edited shortcut never lingers.
    private func registerPresetHotKeys() {
        presetHotKeyIDs.forEach(hotKeys.unregister(id:))
        presetHotKeyIDs = []
        for (index, preset) in controller.presets.presets.enumerated() {
            guard let chord = preset.hotKey, chord != settings.hotKey else { continue }
            let id = Self.presetHotKeyBase + UInt32(index)
            let presetID = preset.id
            hotKeys.register(id: id, chord: chord) { [weak self] in
                self?.controller.runPresetFromHotKey(presetID)
            }
            presetHotKeyIDs.append(id)
        }
    }

    private static func supportDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let url = base.appending(path: "Comet", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    // MARK: - Menus

    /// An accessory app has no visible menu bar, but text fields still need ⌘C, ⌘V and ⌘A.
    private func installMainMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Settings…", action: #selector(showSettingsAction), keyEquivalent: ",")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Comet 42", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        let paste = edit.addItem(withTitle: "Paste", action: #selector(smartPaste(_:)), keyEquivalent: "v")
        paste.target = self
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)
        NSApp.mainMenu = main
    }

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = CometGlyph.menuBarImage()
        let menu = NSMenu()
        let open = menu.addItem(withTitle: "Open Comet 42", action: #selector(openPanel), keyEquivalent: "")
        open.target = self
        menu.addItem(.separator())
        let settings = menu.addItem(withTitle: "Settings…", action: #selector(showSettingsAction), keyEquivalent: ",")
        settings.target = self
        let welcome = menu.addItem(withTitle: "Welcome…", action: #selector(showOnboardingAction), keyEquivalent: "")
        welcome.target = self
        let check = menu.addItem(withTitle: "Check AI Tools Again", action: #selector(recheck), keyEquivalent: "")
        check.target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Comet 42", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        statusItem = item
    }

    /// In the panel, ⌘V stages pictures, files and long text as chips; elsewhere it is plain paste.
    @objc private func smartPaste(_ sender: Any?) {
        guard NSApp.keyWindow is CometPanel else {
            NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: sender)
            return
        }
        guard let inline = controller.pasteFromClipboard() else { return }
        let editor = NSApp.keyWindow?.firstResponder as? NSTextView
        if let editor, editor.isEditable {
            editor.insertText(inline, replacementRange: editor.selectedRange())
        } else {
            controller.session.draft += inline
        }
    }

    @objc private func openPanel() {
        Task { await controller.summon() }
    }

    @objc private func recheck() {
        controller.backends.refresh()
    }

    @objc private func showSettingsAction() {
        showSettings()
    }

    private func showSettings() {
        panel.hide()
        if settingsWindow == nil {
            let view = SettingsView(
                controller: controller, hotKeys: hotKeys,
                applyHotKey: { [weak self] in self?.applyHotKey() ?? false })
            let window = NSWindow(contentViewController: NSHostingController(rootView: view))
            window.title = "Comet 42 Settings"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            // A unified toolbar is what gives the sidebar its full-height, System Settings look.
            window.toolbar = NSToolbar(identifier: "CometSettings")
            window.toolbarStyle = .unified
            window.titlebarAppearsTransparent = true
            // Each page names itself in its header, so the window title would only repeat it.
            window.titleVisibility = .hidden
            window.setContentSize(NSSize(width: 900, height: 640))
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            settingsWindow = window
        }
        // An accessory app's activation request is often refused; a regular one's is honoured,
        // and Settings then also shows in the Dock and ⌘-Tab while it is open.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        settingsWindow?.makeKeyAndOrderFront(nil)
        settingsWindow?.orderFrontRegardless()
    }

    @objc private func showOnboardingAction() {
        showOnboarding()
    }

    private func showOnboarding() {
        panel.hide()
        if onboardingWindow == nil {
            let view = OnboardingView(
                controller: controller, hotKeys: hotKeys,
                applyHotKey: { [weak self] in self?.applyHotKey() ?? false },
                onFinish: { [weak self] tryIt in self?.finishOnboarding(tryIt: tryIt) })
            let window = NSWindow(contentViewController: NSHostingController(rootView: view))
            window.title = "Welcome to Comet 42"
            window.styleMask = [.titled, .closable, .fullSizeContentView]
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            onboardingWindow = window
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        onboardingWindow?.makeKeyAndOrderFront(nil)
        onboardingWindow?.orderFrontRegardless()
    }

    private func finishOnboarding(tryIt: Bool) {
        settings.hasCompletedOnboarding = true
        onboardingWindow?.close()
        guard tryIt else { return }
        Task { await controller.summon() }
    }

    func windowWillClose(_ notification: Notification) {
        let closing = notification.object as? NSWindow
        if closing === onboardingWindow {
            // Closing the window is also an answer: it should not come back on every launch.
            settings.hasCompletedOnboarding = true
            onboardingWindow = nil
        } else if closing !== settingsWindow {
            return
        }
        // Back to menu-bar only once neither Settings nor onboarding is on screen.
        let stillOpen = [settingsWindow, onboardingWindow].contains {
            $0 != nil && $0 !== closing && $0?.isVisible == true
        }
        if !stillOpen { NSApp.setActivationPolicy(.accessory) }
    }
}
