import AppKit
import SwiftUI

/// Takes key focus for typing without activating the app, so the source app stays frontmost.
final class CometPanel: NSPanel {
    var onCancel: () -> Void = {}
    var onReset: () -> Void = {}

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        onCancel()
    }

    /// Zoom (from VoiceOver or a menu) would fill the screen; here it means "put it back".
    override func zoom(_ sender: Any?) {
        onReset()
    }

    override func accessibilityRole() -> NSAccessibility.Role? { .window }
    override func accessibilitySubrole() -> NSAccessibility.Subrole? { .floatingWindow }
}

/// Owns the panel's frame: where it opens, how wide the reader made it, and how tall it grows.
final class CometPanelController: NSObject, NSWindowDelegate {
    private let controller: CometController
    private lazy var panel: CometPanel = makePanel()
    private var settings: AppSettings { controller.settings }

    /// Measured by the view: everything but the transcript, and the transcript's own content.
    private var chromeHeight: CGFloat = 160
    private var transcriptHeight: CGFloat?
    private var isLiveResizing = false
    /// Our own frame changes must not be saved as if the reader had dragged the panel there.
    private var isPlacing = false

    static let minWidth: CGFloat = 440
    private static let screenMargin: CGFloat = 12

    init(controller: CometController) {
        self.controller = controller
    }

    var isVisible: Bool { panel.isVisible }
    var windowNumber: Int { panel.windowNumber }

    func show() {
        if !panel.isVisible { place() }
        fit()
        panel.makeKeyAndOrderFront(nil)
    }

    func hide() {
        panel.orderOut(nil)
    }

    /// Back to the designed width and height, opened where a fresh install would open it.
    func resetGeometry() {
        settings.panelWidth = AppSettings.defaultPanelWidth
        settings.panelMaxHeight = AppSettings.defaultPanelMaxHeight
        settings.panelTopLeft = nil
        place()
        fit()
    }

    /// Called by the view whenever its measured parts change size.
    func contentMetricsChanged(chrome: CGFloat, transcript: CGFloat?) {
        chromeHeight = chrome
        transcriptHeight = transcript
        fit()
    }

    // MARK: - Geometry

    private var idealHeight: CGFloat {
        chromeHeight + (transcriptHeight.map { $0 + 1 } ?? 0)
    }

    private func place() {
        isPlacing = true
        defer { isPlacing = false }
        let screen = targetScreen()
        let visible = screen.visibleFrame
        let width = min(
            max(CGFloat(settings.panelWidth), Self.minWidth), visible.width - 2 * Self.screenMargin)
        var frame = panel.frame
        frame.size.width = width
        let topLeft: NSPoint
        if settings.remembersPanelPosition, let saved = savedTopLeft(),
            NSScreen.screens.contains(where: { $0.visibleFrame.contains(saved) })
        {
            topLeft = saved
        } else {
            // Upper third of the screen with the pointer, where Spotlight-style panels are expected.
            topLeft = NSPoint(
                x: visible.midX - width / 2, y: visible.minY + visible.height * 0.78)
        }
        frame.origin = NSPoint(x: topLeft.x, y: topLeft.y - frame.height)
        panel.setFrame(clamped(frame, to: visible), display: false)
    }

    /// Grows downward from a fixed top edge, up to the reader's chosen ceiling and the screen.
    private func fit() {
        // Before the first layout the view measures zero; fitting to that would collapse the window.
        guard !isLiveResizing, chromeHeight > 40 else { return }
        isPlacing = true
        defer { isPlacing = false }
        let visible = (panel.screen ?? targetScreen()).visibleFrame
        let ceiling = min(CGFloat(settings.panelMaxHeight), visible.height - 2 * Self.screenMargin)
        let target = max(chromeHeight, min(idealHeight, max(ceiling, chromeHeight))).rounded()
        // Without a chat there is nothing to show in extra height, so only the width resizes.
        panel.contentMinSize = NSSize(width: Self.minWidth, height: chromeHeight)
        panel.contentMaxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: transcriptHeight == nil ? chromeHeight : CGFloat.greatestFiniteMagnitude)
        var frame = panel.frame
        guard abs(frame.height - target) > 0.5 || !visible.contains(frame) else { return }
        let top = frame.maxY
        frame.size.height = target
        frame.origin.y = top - target
        panel.setFrame(clamped(frame, to: visible), display: true)
    }

    private func clamped(_ frame: NSRect, to visible: NSRect) -> NSRect {
        var frame = frame
        let margin = Self.screenMargin
        frame.size.width = min(frame.width, visible.width - 2 * margin)
        frame.size.height = min(frame.height, visible.height - 2 * margin)
        frame.origin.x = min(max(frame.minX, visible.minX + margin), visible.maxX - margin - frame.width)
        frame.origin.y = min(max(frame.minY, visible.minY + margin), visible.maxY - margin - frame.height)
        return frame
    }

    private func targetScreen() -> NSScreen {
        if settings.remembersPanelPosition, let saved = savedTopLeft(),
            let screen = NSScreen.screens.first(where: { $0.visibleFrame.contains(saved) })
        {
            return screen
        }
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
            ?? NSScreen.screens[0]
    }

    private func savedTopLeft() -> NSPoint? {
        guard let saved = settings.panelTopLeft, saved.count == 2 else { return nil }
        return NSPoint(x: saved[0], y: saved[1])
    }

    private func savePosition() {
        guard !isPlacing, panel.isVisible else { return }
        settings.panelTopLeft = [Double(panel.frame.minX), Double(panel.frame.maxY)]
    }

    // MARK: - Window

    private func makePanel() -> CometPanel {
        let panel = CometPanel(
            contentRect: NSRect(x: 0, y: 0, width: settings.panelWidth, height: 200),
            // Borderless: a hidden title bar still reserves a safe area and bends the content size.
            styleMask: [.borderless, .nonactivatingPanel, .resizable],
            backing: .buffered, defer: true)
        // Never drawn, but VoiceOver names the window by it.
        panel.title = "Comet 42"
        panel.isMovableByWindowBackground = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.delegate = self
        panel.onCancel = { [weak self] in self?.hide() }
        panel.onReset = { [weak self] in self?.resetGeometry() }
        let view = CometView(controller: controller) { [weak self] chrome, transcript in
            self?.contentMetricsChanged(chrome: chrome, transcript: transcript)
        }
        let host = NSHostingView(rootView: view)
        // The window's frame is ours to set; the content fills whatever it is given.
        host.sizingOptions = []
        panel.contentView = host
        panel.contentMinSize = NSSize(width: Self.minWidth, height: 120)
        return panel
    }

    func windowWillStartLiveResize(_ notification: Notification) {
        isLiveResizing = true
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        isLiveResizing = false
        settings.panelWidth = Double(panel.frame.width)
        // Dragging the bottom edge with a chat showing sets how tall later chats may grow.
        if transcriptHeight != nil { settings.panelMaxHeight = Double(panel.frame.height) }
        savePosition()
        fit()
    }

    func windowDidMove(_ notification: Notification) {
        savePosition()
    }

    func windowDidResignKey(_ notification: Notification) {
        // A Replace hides the panel itself; this covers a click into another app.
        guard settings.hidesOnFocusLoss, panel.isVisible, panel.attachedSheet == nil else { return }
        Task { @MainActor [weak self] in
            // A menu popping up briefly takes key status; only a real loss of focus hides.
            try? await Task.sleep(for: .milliseconds(150))
            guard let self, self.panel.isVisible, !self.panel.isKeyWindow else { return }
            self.hide()
        }
    }
}
