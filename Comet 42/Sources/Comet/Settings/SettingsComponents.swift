import AppKit
import SwiftUI

// Building blocks shared by Settings and onboarding.

/// A white glyph on a rounded colour tile, as System Settings draws its sidebar.
struct IconTile: View {
    let symbol: String
    let color: Color
    var size: CGFloat = 22

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
            .fill(color.gradient)
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: symbol)
                    .font(.system(size: size * 0.54, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .accessibilityHidden(true)
    }
}

/// A toggle with a second line explaining what it does.
struct DescribedToggle: View {
    let title: String
    let detail: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

/// A shortcut written as key caps, the way macOS menus show them.
struct KeyCaps: View {
    let keys: [String]

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(keys.enumerated()), id: \.offset) { _, key in
                Text(key)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.08)))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4).strokeBorder(Color.primary.opacity(0.15)))
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct ShortcutTip: View {
    let keys: [String]
    let text: String

    var body: some View {
        LabeledContent {
            KeyCaps(keys: keys)
        } label: {
            Text(text)
        }
    }
}

struct StatusBadge: View {
    let text: String
    let color: Color

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(text).font(.caption.weight(.medium))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(color.opacity(0.14), in: Capsule())
        .accessibilityElement(children: .combine)
    }
}

/// Click, then press the new chord; every hotkey is paused while recording so any combo lands.
struct HotKeyRecorder: View {
    let chord: HotKeyChord?
    let hotKeys: HotKeyCenter
    var placeholder = "Record Shortcut"
    let onChange: (HotKeyChord) -> Void
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        Button {
            recording ? stop() : start()
        } label: {
            HStack(spacing: 6) {
                if recording {
                    Image(systemName: "record.circle").foregroundStyle(.red)
                    Text("Press a shortcut…")
                } else {
                    Text(chord?.displayString ?? placeholder)
                        .font(.system(.body, design: .rounded).weight(.medium))
                        .foregroundStyle(chord == nil ? .secondary : .primary)
                }
            }
            .frame(minWidth: 130)
        }
        .controlSize(.large)
        .help(recording ? "Press the new shortcut, or Esc to cancel" : "Click to record a new shortcut")
        .accessibilityLabel(
            recording ? "Recording shortcut" : chord.map { "Shortcut \($0.displayString)" } ?? placeholder)
        .accessibilityHint("Activate, then press the new key combination")
        .onDisappear(perform: stop)
    }

    private func start() {
        recording = true
        hotKeys.isPaused = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 {  // Escape cancels.
                stop()
                return nil
            }
            guard let chord = HotKeyChord(event: event) else { return nil }
            stop()
            onChange(chord)
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recording = false
        hotKeys.isPaused = false
    }
}

struct ToolCard: View {
    let backend: AIBackend
    let status: BackendStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                IconTile(
                    symbol: backend == .claude ? "sparkle" : "chevron.left.forwardslash.chevron.right",
                    color: backend == .claude ? .orange : .teal, size: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(backend.title + " CLI").font(.headline)
                    Text(status.version ?? "—").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if status.phase == .checking {
                    ProgressView().controlSize(.small)
                }
                StatusBadge(text: badgeText, color: color)
            }
            if let path = status.executable?.path {
                Text(path)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            if let command = fixCommand {
                HStack {
                    Text(command)
                        .font(.system(size: 12, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                    Button("Copy") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(command, forType: .string)
                    }
                    .accessibilityLabel("Copy command: \(command)")
                    Spacer()
                }
                Text(status.phase == .notInstalled
                    ? "Run this in Terminal to install, then Check Again."
                    : "Run this in Terminal to sign in, then Check Again.")
                    .font(.caption).foregroundStyle(.secondary)
            } else if status.isReady, !status.models.isEmpty {
                Text("\(status.models.count) models available")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private var badgeText: String {
        switch status.phase {
        case .ready: return "Ready"
        case .checking, .idle: return "Checking"
        case .signInRequired: return "Signed out"
        case .notInstalled: return "Not installed"
        case .failed: return "Problem"
        }
    }

    private var color: Color {
        switch status.phase {
        case .ready: return .green
        case .checking, .idle: return .gray
        case .signInRequired: return .orange
        case .notInstalled, .failed: return .red
        }
    }

    private var fixCommand: String? {
        switch status.phase {
        case .notInstalled: return backend.installHint
        case .signInRequired: return backend.signInCommand
        default: return nil
        }
    }
}
