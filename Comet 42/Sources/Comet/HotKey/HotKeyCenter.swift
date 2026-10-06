import AppKit
import Carbon.HIToolbox

private func hotKeyCarbonEventHandler(
    _: EventHandlerCallRef?, event: EventRef?, userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event, let userData else { return OSStatus(eventNotHandledErr) }
    var hotKeyID = EventHotKeyID()
    let error = GetEventParameter(
        event, UInt32(kEventParamDirectObject), UInt32(typeEventHotKeyID), nil,
        MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
    guard error == noErr else { return error }
    let center = Unmanaged<HotKeyCenter>.fromOpaque(userData).takeUnretainedValue()
    return center.handle(hotKeyID)
}

/// Carbon is the deliberate dependency here: nothing modern registers a system-wide chord.
final class HotKeyCenter {
    private struct Entry {
        let chord: HotKeyChord
        let action: () -> Void
        var ref: EventHotKeyRef?
    }

    private var entries: [UInt32: Entry] = [:]
    private var eventHandler: EventHandlerRef?
    private let signature: OSType = 0x434D_4554  // FourCC "CMET"

    /// While true every hotkey is unregistered, so the recorder can capture any combo.
    var isPaused = false {
        didSet {
            guard isPaused != oldValue else { return }
            for id in entries.keys {
                if isPaused { deactivate(id) } else { activate(id) }
            }
        }
    }

    /// Returns false when another app already owns the chord.
    @discardableResult
    func register(id: UInt32, chord: HotKeyChord, action: @escaping () -> Void) -> Bool {
        unregister(id: id)
        entries[id] = Entry(chord: chord, action: action, ref: nil)
        guard !isPaused else { return true }
        return activate(id)
    }

    func unregister(id: UInt32) {
        guard let entry = entries.removeValue(forKey: id) else { return }
        if let ref = entry.ref { UnregisterEventHotKey(ref) }
    }

    @discardableResult
    private func activate(_ id: UInt32) -> Bool {
        guard var entry = entries[id] else { return false }
        guard entry.ref == nil else { return true }
        installEventHandlerIfNeeded()
        var ref: EventHotKeyRef?
        let error = RegisterEventHotKey(
            entry.chord.keyCode, entry.chord.modifiers,
            EventHotKeyID(signature: signature, id: id), GetEventDispatcherTarget(), 0, &ref)
        guard error == noErr, let ref else {
            NSLog("Comet 42: could not register hotkey %u (OSStatus %d)", id, error)
            return false
        }
        entry.ref = ref
        entries[id] = entry
        return true
    }

    private func deactivate(_ id: UInt32) {
        guard var entry = entries[id], let ref = entry.ref else { return }
        UnregisterEventHotKey(ref)
        entry.ref = nil
        entries[id] = entry
    }

    private func installEventHandlerIfNeeded() {
        guard eventHandler == nil, let dispatcher = GetEventDispatcherTarget() else { return }
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(
            dispatcher,
            { call, event, userData in
                MainActor.assumeIsolated {
                    hotKeyCarbonEventHandler(call, event: event, userData: userData)
                }
            },
            1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &eventHandler)
    }

    fileprivate func handle(_ hotKeyID: EventHotKeyID) -> OSStatus {
        guard hotKeyID.signature == signature, let entry = entries[hotKeyID.id] else {
            return OSStatus(eventNotHandledErr)
        }
        entry.action()
        return noErr
    }
}

extension HotKeyChord {
    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var carbon: UInt32 = 0
        if flags.contains(.command) { carbon |= UInt32(cmdKey) }
        if flags.contains(.option) { carbon |= UInt32(optionKey) }
        if flags.contains(.control) { carbon |= UInt32(controlKey) }
        if flags.contains(.shift) { carbon |= UInt32(shiftKey) }
        // A bare key would swallow ordinary typing everywhere; function keys are the exception.
        let isFunctionKey = (0x60...0x7A).contains(Int(event.keyCode))
        guard carbon != 0 || isFunctionKey else { return nil }
        self.init(keyCode: UInt32(event.keyCode), modifiers: carbon)
    }

    var displayString: String {
        var result = ""
        if modifiers & UInt32(controlKey) != 0 { result += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { result += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { result += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { result += "⌘" }
        return result + Self.keyName(Int(keyCode))
    }

    private static func keyName(_ code: Int) -> String {
        switch code {
        case kVK_Space: return "Space"
        case kVK_Return: return "↩"
        case kVK_Tab: return "⇥"
        case kVK_Escape: return "⎋"
        case kVK_Delete: return "⌫"
        case kVK_F1: return "F1"
        case kVK_F2: return "F2"
        case kVK_F3: return "F3"
        case kVK_F4: return "F4"
        case kVK_F5: return "F5"
        case kVK_F6: return "F6"
        case kVK_F7: return "F7"
        case kVK_F8: return "F8"
        case kVK_F9: return "F9"
        case kVK_F10: return "F10"
        case kVK_F11: return "F11"
        case kVK_F12: return "F12"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        default: return layoutCharacter(code) ?? "Key \(code)"
        }
    }

    /// The character the current keyboard layout prints for the key, so ⌥Q reads as ⌥Q on AZERTY.
    private static func layoutCharacter(_ code: Int) -> String? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
            let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data
        return data.withUnsafeBytes { raw -> String? in
            guard let layout = raw.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self)
            else { return nil }
            var deadKeys: UInt32 = 0
            var length = 0
            var chars = [UniChar](repeating: 0, count: 4)
            let status = UCKeyTranslate(
                layout, UInt16(code), UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeys, chars.count, &length, &chars)
            guard status == noErr, length > 0 else { return nil }
            return String(utf16CodeUnits: chars, count: length).uppercased()
        }
    }
}
