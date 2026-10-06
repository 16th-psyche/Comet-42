import AppKit
import SwiftUI

/// First-run setup: what Comet 42 is, its AI tools, the Accessibility permission, the shortcut.
struct OnboardingView: View {
    let controller: CometController
    let hotKeys: HotKeyCenter
    let applyHotKey: () -> Bool
    let onFinish: (_ tryIt: Bool) -> Void

    private enum Step: Int, CaseIterable {
        case welcome
        case tools
        case permission
        case shortcut
    }

    @State private var step = Step.welcome
    @State private var hotKeyFailed = false
    @State private var launchesAtLogin = LaunchAtLogin.isEnabled
    @State private var loginError: String?

    private var settings: AppSettings { controller.settings }
    private var anyToolReady: Bool { AIBackend.allCases.contains { controller.backends.status($0).isReady } }

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch step {
                case .welcome: welcome
                case .tools: tools
                case .permission: permission
                case .shortcut: shortcut
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.horizontal, 36)
            .padding(.top, 32)
            Divider()
            footer
        }
        .frame(width: 600, height: 520)
    }

    // MARK: - Steps

    private var welcome: some View {
        VStack(spacing: 16) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 110, height: 110)
                .accessibilityHidden(true)
            Text("Welcome to Comet 42").font(.largeTitle.weight(.semibold))
            Text("Ask AI about anything on your screen without leaving the app you're in.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            VStack(alignment: .leading, spacing: 12) {
                Feature(symbol: "text.cursor", text: "Select text, paste content or capture part of the screen")
                Feature(symbol: "wand.and.sparkles", text: "Ask a question, or run a preset like Improve Writing")
                Feature(symbol: "arrow.uturn.left.circle", text: "Replace your selection with the result, in place")
            }
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
    }

    private var tools: some View {
        StepLayout(
            number: 1, title: "Connect an AI tool",
            detail: "Comet 42 uses the Claude or Codex command-line tool you sign in to. It never asks for an API key. You need at least one showing Ready."
        ) {
            VStack(spacing: 10) {
                ForEach(AIBackend.allCases) { backend in
                    ToolCard(backend: backend, status: controller.backends.status(backend))
                        .padding(12)
                        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
                }
                HStack {
                    Spacer()
                    Button {
                        controller.backends.refresh()
                    } label: {
                        Label("Check Again", systemImage: "arrow.clockwise")
                    }
                }
            }
        }
    }

    private var permission: some View {
        StepLayout(
            number: 2, title: "Allow Accessibility",
            detail: "macOS asks for this so Comet 42 can read the text you select and paste results back. Nothing is read until you press the shortcut."
        ) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    IconTile(symbol: "accessibility", color: .blue, size: 36)
                    Text("Accessibility").font(.headline)
                    Spacer()
                    if controller.accessibilityTrusted {
                        StatusBadge(text: "Allowed", color: .green)
                    } else {
                        StatusBadge(text: "Not allowed yet", color: .orange)
                    }
                }
                if !controller.accessibilityTrusted {
                    Button("Open Accessibility Settings") {
                        Permissions.ensureAccessibility()
                        Permissions.openAccessibilitySettings()
                    }
                    .controlSize(.large)
                    Text("Turn on **Comet 42** in the list. This page updates by itself.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Divider().padding(.vertical, 4)
                Label {
                    Text("The **Capture** button asks for Screen Recording the first time you use it. That one is optional.")
                        .font(.callout).foregroundStyle(.secondary)
                } icon: {
                    Image(systemName: "camera.viewfinder").foregroundStyle(.secondary)
                }
            }
        }
        .onAppear { controller.refreshAccessibilityTrust() }
    }

    private var shortcut: some View {
        @Bindable var settings = settings
        return StepLayout(
            number: 3, title: "Pick your shortcut",
            detail: "Press it in any app to open Comet 42. Choose one that no other app uses. Raycast, ChatGPT and Spotlight alternatives often take ⌥Space."
        ) {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Open Comet 42")
                    Spacer()
                    HotKeyRecorder(chord: settings.hotKey, hotKeys: hotKeys) { chord in
                        settings.hotKey = chord
                        hotKeyFailed = !applyHotKey()
                    }
                }
                if hotKeyFailed {
                    Label("Another app already uses that shortcut. Pick a different one.",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.callout).foregroundStyle(.orange)
                }
                Divider()
                Toggle(isOn: $launchesAtLogin) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Open Comet 42 when you log in")
                        Text("So the shortcut always works.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .onChange(of: launchesAtLogin) {
                    loginError = LaunchAtLogin.set(launchesAtLogin)
                    if loginError != nil { launchesAtLogin = LaunchAtLogin.isEnabled }
                }
                if let loginError {
                    Text(loginError).font(.caption).foregroundStyle(.orange)
                }
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            HStack(spacing: 6) {
                ForEach(Step.allCases, id: \.rawValue) { item in
                    Circle()
                        .fill(item == step ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(width: 7, height: 7)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Page \(step.rawValue + 1) of \(Step.allCases.count)")
            Spacer()
            if step != .welcome {
                Button("Back") { move(-1) }
            }
            if step == .shortcut {
                Button("Done") { onFinish(false) }
                Button("Try It Now") { onFinish(true) }
                    .keyboardShortcut(.defaultAction)
            } else {
                Button(nextTitle) { move(1) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
    }

    private var nextTitle: String {
        switch step {
        case .welcome: return "Get Started"
        case .tools: return anyToolReady ? "Continue" : "Continue Anyway"
        case .permission: return controller.accessibilityTrusted ? "Continue" : "Later"
        case .shortcut: return "Done"
        }
    }

    private func move(_ offset: Int) {
        guard let next = Step(rawValue: step.rawValue + offset) else { return }
        withAnimation(.easeInOut(duration: 0.2)) { step = next }
    }
}

private struct Feature: View {
    let symbol: String
    let text: String

    var body: some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: symbol).foregroundStyle(.tint).frame(width: 22)
        }
        .font(.body)
    }
}

private struct StepLayout<Content: View>: View {
    let number: Int
    let title: String
    let detail: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("STEP \(number) OF 3")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(title).font(.title.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                Text(detail)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            content
        }
    }
}
