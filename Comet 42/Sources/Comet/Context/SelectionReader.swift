import AppKit
@preconcurrency import ApplicationServices
import Carbon.HIToolbox

enum Permissions {
    static var isAccessibilityTrusted: Bool { AXIsProcessTrusted() }

    /// Prompts once from a gesture that needs it; returns whether the app is already trusted.
    @discardableResult
    static func ensureAccessibility() -> Bool {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    static func openAccessibilitySettings() {
        if let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        {
            NSWorkspace.shared.open(url)
        }
    }
}

/// Always against a named process: the system-wide focus answers with ours.
enum AccessibilityText {
    private static let timeout: Float = 1

    enum Selection: Equatable {
        case text(String)
        case noFocusedElement
        case empty
    }

    static func focusedElement(in app: NSRunningApplication) -> AXUIElement? {
        let application = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(application, timeout)
        // Chromium builds its tree only once asked, so Chrome and Electron answer nothing until this.
        AXUIElementSetAttributeValue(
            application, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        var focusedValue: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(
                application, kAXFocusedUIElementAttribute as CFString, &focusedValue) == .success,
            let focusedValue,
            CFGetTypeID(focusedValue) == AXUIElementGetTypeID()
        else { return nil }
        let element = focusedValue as! AXUIElement
        AXUIElementSetMessagingTimeout(element, timeout)
        return element
    }

    static func read(in app: NSRunningApplication) -> Selection {
        guard let element = focusedElement(in: app) else { return .noFocusedElement }
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(
            element, kAXSelectedTextAttribute as CFString, &value)
        if status == .success, let text = value as? String, !text.isEmpty { return .text(text) }
        guard let web = webSelection(in: element), !web.isEmpty else { return .empty }
        return .text(web)
    }

    /// Whether the focused element takes typing; nil when the app exposes no focused element.
    static func isEditable(in app: NSRunningApplication) -> Bool? {
        guard let element = focusedElement(in: app) else { return nil }
        var settable: DarwinBoolean = false
        if AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &settable)
            == .success, settable.boolValue
        {
            return true
        }
        var role: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)
        let editableRoles = ["AXTextField", "AXTextArea", "AXComboBox", "AXSearchField"]
        if let role = role as? String, editableRoles.contains(role) { return true }
        var editable: CFTypeRef?
        // Web content marks contenteditable regions with this private-but-stable attribute.
        if AXUIElementCopyAttributeValue(element, "AXEditableAncestor" as CFString, &editable)
            == .success, editable != nil
        {
            return true
        }
        return false
    }

    /// Whether the app's ⌘C menu item is enabled; nil when its menu can't be read.
    /// Found by shortcut, not title, so it works in every language.
    static func copyIsEnabled(in app: NSRunningApplication) -> Bool? {
        let application = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(application, timeout)
        var bar: CFTypeRef?
        guard AXUIElementCopyAttributeValue(application, kAXMenuBarAttribute as CFString, &bar)
            == .success, let bar, CFGetTypeID(bar) == AXUIElementGetTypeID()
        else { return nil }
        guard let item = copyItem(in: bar as! AXUIElement, depth: 0) else { return nil }
        var enabled: CFTypeRef?
        guard AXUIElementCopyAttributeValue(item, kAXEnabledAttribute as CFString, &enabled) == .success
        else { return nil }
        return (enabled as? Bool) ?? (enabled as? NSNumber)?.boolValue
    }

    /// Menu bar → menu bar item → menu → item: three levels is where ⌘C always lives.
    private static func copyItem(in element: AXUIElement, depth: Int) -> AXUIElement? {
        guard depth <= 3 else { return nil }
        var children: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children)
        for child in (children as? [AXUIElement]) ?? [] {
            var key: CFTypeRef?
            var modifiers: CFTypeRef?
            AXUIElementCopyAttributeValue(child, kAXMenuItemCmdCharAttribute as CFString, &key)
            AXUIElementCopyAttributeValue(child, kAXMenuItemCmdModifiersAttribute as CFString, &modifiers)
            // Modifier bits 0 mean ⌘ alone; ⇧⌘C and ⌥⌘C are other commands.
            if (key as? String) == "C", (modifiers as? NSNumber)?.intValue == 0 { return child }
            if let found = copyItem(in: child, depth: depth + 1) { return found }
        }
        return nil
    }

    /// Browsers have no `AXSelectedText`: web selection exists only as an opaque marker range.
    private static func webSelection(in element: AXUIElement) -> String? {
        var range: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(
                element, kAXSelectedTextMarkerRangeAttribute as CFString, &range) == .success,
            let range,
            CFGetTypeID(range) == AXTextMarkerRangeGetTypeID()
        else { return nil }
        var value: CFTypeRef?
        guard
            AXUIElementCopyParameterizedAttributeValue(
                element, kAXStringForTextMarkerRangeParameterizedAttribute as CFString, range,
                &value) == .success
        else { return nil }
        return value as? String
    }
}

/// Reads what the reader has selected in the frontmost app, without leaving a trace on the clipboard.
enum SelectionReader {
    static let maxSelectionBytes = 32_768

    static func selection(in app: NSRunningApplication?) async -> String? {
        guard let app, app.bundleIdentifier != Bundle.main.bundleIdentifier,
            Permissions.isAccessibilityTrusted
        else { return nil }
        let text: String?
        switch AccessibilityText.read(in: app) {
        case .text(let found):
            text = found
        case .empty, .noFocusedElement:
            // A disabled Copy means nothing is selected, and ⌘C would only play the alert sound.
            guard AccessibilityText.copyIsEnabled(in: app) != false else { return nil }
            // A borrowed ⌘C synthesises a keystroke into somebody's app, so it is never the first try.
            text = await copySelection(from: app)
        }
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        guard text.utf8.count <= maxSelectionBytes else {
            return String(text.utf8.prefix(maxSelectionBytes)) ?? String(text.prefix(8_000))
        }
        return text
    }

    private static func copySelection(from app: NSRunningApplication) async -> String? {
        let pasteboard = NSPasteboard.general
        let snapshot = PasteboardSnapshot(pasteboard)
        defer { snapshot.restore(to: pasteboard) }
        // Sent to the app itself: it arrives even while the panel has key focus, and the reader's
        // still-held hotkey modifiers cannot join the chord.
        KeySynth.command(CGKeyCode(kVK_ANSI_C), toPid: app.processIdentifier)
        // A copy lands within a few frames; half a second is the most an answer is worth waiting.
        for _ in 0..<20 {
            try? await Task.sleep(for: .milliseconds(25))
            guard pasteboard.changeCount != snapshot.changeCount else { continue }
            return pasteboard.string(forType: .string)
        }
        return nil
    }
}

/// Every item and type on the pasteboard, so a borrowed copy or paste can put it all back.
struct PasteboardSnapshot {
    let changeCount: Int
    private let items: [[NSPasteboard.PasteboardType: Data]]

    init(_ pasteboard: NSPasteboard) {
        changeCount = pasteboard.changeCount
        items = (pasteboard.pasteboardItems ?? []).map { item in
            var types: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) { types[type] = data }
            }
            return types
        }
    }

    func restore(to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        let restored = items.map { types -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in types { item.setData(data, forType: type) }
            return item
        }
        if !restored.isEmpty { pasteboard.writeObjects(restored) }
    }
}

enum KeySynth {
    /// Tags our own synthesised keystrokes, so they can be told apart from the reader's.
    private static let eventTag: Int64 = 0x434D_4554

    static func command(_ key: CGKeyCode, toPid pid: pid_t? = nil) {
        press(key, flags: .maskCommand, toPid: pid)
    }

    /// A key with no modifiers, such as → to collapse a selection to its end.
    static func plain(_ key: CGKeyCode) {
        press(key, flags: [])
    }

    private static func press(_ key: CGKeyCode, flags: CGEventFlags, toPid pid: pid_t? = nil) {
        // A private source: the reader's still-held hotkey modifiers must not join this chord.
        let source = CGEventSource(stateID: .privateState)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true),
            let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false)
        else { return }
        down.flags = flags
        up.flags = flags
        down.setIntegerValueField(.eventSourceUserData, value: eventTag)
        up.setIntegerValueField(.eventSourceUserData, value: eventTag)
        if let pid {
            down.postToPid(pid)
            up.postToPid(pid)
        } else {
            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
        }
    }

    /// The hotkey fires on key-down, while ⌥ is still held; a ⌘C sent then can arrive as ⌥⌘C.
    static func waitForModifierRelease() async {
        for _ in 0..<20 {
            let held = NSEvent.modifierFlags.intersection([.option, .control, .shift, .command])
            if held.isEmpty { return }
            try? await Task.sleep(for: .milliseconds(20))
        }
    }
}
