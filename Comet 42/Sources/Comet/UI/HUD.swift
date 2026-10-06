import AppKit
import SwiftUI

@Observable
final class HUDState {
    enum Tone {
        case neutral
        case danger
    }

    var message = ""
    var tone = Tone.neutral
    var isProgress = false
    @ObservationIgnored var onCancel: (() -> Void)?
}

/// A small pill near the bottom of the screen: progress for a direct preset, or a short report.
final class HUDController {
    private let state = HUDState()
    private lazy var panel: NSPanel = makePanel()
    private var hideTask: Task<Void, Never>?

    func progress(_ message: String, onCancel: @escaping () -> Void) {
        state.message = message
        state.tone = .neutral
        state.isProgress = true
        state.onCancel = onCancel
        present(autoHide: false)
    }

    func show(_ message: String, tone: HUDState.Tone = .neutral) {
        state.message = message
        state.tone = tone
        state.isProgress = false
        state.onCancel = nil
        present(autoHide: true, seconds: tone == .danger ? 4 : 1.6)
    }

    func hide() {
        hideTask?.cancel()
        panel.orderOut(nil)
    }

    private func present(autoHide: Bool, seconds: Double = 1.6) {
        hideTask?.cancel()
        let size = panel.contentView?.fittingSize ?? NSSize(width: 260, height: 44)
        let screen = NSScreen.main ?? NSScreen.screens.first
        if let frame = screen?.visibleFrame {
            panel.setFrame(
                NSRect(
                    x: frame.midX - size.width / 2, y: frame.minY + 80, width: size.width,
                    height: size.height), display: true)
        }
        panel.orderFrontRegardless()
        guard autoHide else { return }
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.panel.orderOut(nil)
        }
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 260, height: 44),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        let host = NSHostingView(rootView: HUDView(state: state))
        host.sizingOptions = [.intrinsicContentSize]
        panel.contentView = host
        return panel
    }
}

private struct HUDView: View {
    let state: HUDState

    var body: some View {
        HStack(spacing: 10) {
            if state.isProgress {
                ProgressView().controlSize(.small)
            } else {
                Image(
                    systemName: state.tone == .danger
                        ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"
                )
                .foregroundStyle(state.tone == .danger ? Color.orange : Color.green)
            }
            Text(state.message)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(3)
                .frame(maxWidth: 420, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            if state.isProgress, let onCancel = state.onCancel {
                Button("Cancel", action: onCancel)
                    .buttonStyle(.borderless)
                    .font(.system(size: 12))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .glassEffect(.regular, in: Capsule())
        .padding(8)
    }
}
