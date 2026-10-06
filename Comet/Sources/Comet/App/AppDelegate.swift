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

    private static let mainHotKeyID: UInt32 = 1

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
        // Asked once here: prompting from the hotkey would steal focus and hide the panel.
        if !Permissions.isAccessibilityTrusted { Permissions.ensureAccessibility() }
        if !applyHotKey() {
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

    func windowWillClose(_ notification: Notification) {
        guard (notification.object as? NSWindow) === settingsWindow else { return }
        NSApp.setActivationPolicy(.accessory)
    }
}
