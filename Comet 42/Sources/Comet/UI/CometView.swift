import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct CometView: View {
    @Bindable var controller: CometController
    /// Reports the measured heights: everything but the chat, and the chat's own content (nil if none).
    let onMetrics: (CGFloat, CGFloat?) -> Void

    @FocusState private var composerFocused: Bool
    @State private var topHeight: CGFloat = 0
    @State private var bottomHeight: CGFloat = 0
    @State private var transcriptHeight: CGFloat = 0
    @State private var searchIndex = 0
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    private var session: CometSession { controller.session }
    private var settings: AppSettings { controller.settings }
    private var palette: PanelPalette { PanelPalette(increasedContrast: contrast == .increased) }
    private var isOpaque: Bool { reduceTransparency || contrast == .increased }

    private struct Metrics: Equatable {
        let chrome: CGFloat
        let transcript: CGFloat?
    }

    private var metrics: Metrics {
        Metrics(
            chrome: (topHeight + bottomHeight).rounded(.up),
            transcript: session.turns.isEmpty ? nil : transcriptHeight.rounded(.up))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(spacing: 0) {
                header
                if !controller.accessibilityTrusted { accessibilityBanner }
            }
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { topHeight = $0 }

            if !session.turns.isEmpty {
                transcript
                Rectangle().fill(palette.border).frame(height: 1)
            }

            VStack(alignment: .leading, spacing: 0) {
                contextBar
                if let query = controller.presetQuery { presetSearch(query) }
                composer
                presetRow
                footer
            }
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { bottomHeight = $0 }
        }
        .frame(
            minWidth: CometPanelController.minWidth, maxWidth: .infinity, maxHeight: .infinity,
            alignment: .top
        )

        .environment(\.uiScale, CGFloat(settings.textScale))
        .background {
            if isOpaque {
                Color(nsColor: .windowBackgroundColor)
            } else {
                Rectangle().fill(.regularMaterial)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(palette.border, lineWidth: isOpaque ? 1.5 : 0.5)
        }
        .overlay(alignment: .bottomTrailing) { ResizeGrip() }
        .background { shortcuts }
        .onDrop(of: [.fileURL, .image, .plainText], isTargeted: nil, perform: handleDrop)
        .onAppear { composerFocused = true }
        .onChange(of: session.turns.count) { composerFocused = true }
        .onChange(of: metrics, initial: true) { onMetrics(metrics.chrome, metrics.transcript) }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "line.3.horizontal")
                .scaledFont(11, weight: .semibold)
                .foregroundStyle(palette.secondary.opacity(0.6))
                .accessibilityHidden(true)
            CometMark(size: 15)
            Text("Comet 42")
                .scaledFont(13, weight: .semibold)
                .accessibilityAddTraits(.isHeader)
            if let app = session.sourceApp, let name = app.localizedName {
                HStack(spacing: 4) {
                    Text("·").foregroundStyle(palette.secondary)
                    if let icon = app.icon {
                        Image(nsImage: icon).resizable().frame(width: 14, height: 14)
                            .accessibilityHidden(true)
                    }
                    Text("from \(name)")
                        .foregroundStyle(palette.secondary)
                        .lineLimit(1)
                }
                .scaledFont(12)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Working with \(name)")
            }
            Spacer(minLength: 8)
            panelMenu
            HeaderIconButton(
                symbol: settings.hidesOnFocusLoss ? "pin" : "pin.fill",
                label: "Keep panel open",
                help: settings.hidesOnFocusLoss
                    ? "Keep the panel open when you click elsewhere"
                    : "Hide the panel when you click elsewhere"
            ) {
                settings.hidesOnFocusLoss.toggle()
            }
            .accessibilityValue(settings.hidesOnFocusLoss ? "Off" : "On")
            HeaderIconButton(symbol: "xmark", label: "Close Comet 42", help: "Close (Esc)") {
                controller.panel?.hide()
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, 8)
        .padding(.vertical, 6)
        .frame(minHeight: 32)
        .contentShape(Rectangle())
        .gesture(WindowDragGesture())
        .simultaneousGesture(TapGesture(count: 2).onEnded { controller.resetPanelGeometry() })
        .pointerStyle(.grabIdle)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Comet 42 title bar")
        .accessibilityHint("Drag to move the panel. Double-click to reset its size and position.")
    }

    private var panelMenu: some View {
        Menu {
            Button("Larger Text") { settings.stepTextScale(by: 0.1) }
            Button("Smaller Text") { settings.stepTextScale(by: -0.1) }
            Button("Actual Size") { settings.textScale = 1 }
            Divider()
            Button("Reset Size and Position") { controller.resetPanelGeometry() }
            Toggle("Remember Position", isOn: Bindable(settings).remembersPanelPosition)
        } label: {
            Image(systemName: "textformat.size")
                .scaledFont(13)
                .frame(width: 26, height: 24)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Text size and panel options (⌘+ ⌘− ⌘0)")
        .accessibilityLabel("Text size and panel options")
    }

    /// Invisible buttons, so the shortcuts work without a menu being open.
    private var shortcuts: some View {
        Group {
            Button("Larger Text") { settings.stepTextScale(by: 0.1) }
                .keyboardShortcut("=", modifiers: .command)
            Button("Larger Text") { settings.stepTextScale(by: 0.1) }
                .keyboardShortcut("+", modifiers: .command)
            Button("Smaller Text") { settings.stepTextScale(by: -0.1) }
                .keyboardShortcut("-", modifiers: .command)
            Button("Actual Size") { settings.textScale = 1 }
                .keyboardShortcut("0", modifiers: .command)
            Button("Reset Panel") { controller.resetPanelGeometry() }
                .keyboardShortcut("0", modifiers: [.command, .option])
            Button("Close") { controller.panel?.hide() }
                .keyboardShortcut("w", modifiers: .command)
            Button("Capture") { controller.captureArea() }
                .keyboardShortcut("s", modifiers: [.command, .shift])
        }
        .opacity(0)
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
    }

    private var accessibilityBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "hand.raised.fill").foregroundStyle(.orange)
                .accessibilityHidden(true)
            Text("Allow Accessibility so Comet 42 can read and replace your selection.")
                .scaledFont(12)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button("Open Settings") { Permissions.openAccessibilitySettings() }
                .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(isOpaque ? 0.2 : 0.1))
        .accessibilityElement(children: .combine)
    }

    // MARK: - Context

    private var contextBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if controller.isCapturing {
                    ProgressView().controlSize(.small)
                        .accessibilityLabel("Reading selection")
                    Text("Reading selection…").scaledFont(12).foregroundStyle(palette.secondary)
                }
                ForEach(session.texts) { text in
                    ContextChip(text: text, palette: palette) { controller.removeText(text.id) }
                }
                ForEach(session.images) { image in
                    ImageChip(image: image, palette: palette) { controller.removeImage(image.id) }
                }
                if let offered = session.offeredImage {
                    Button(action: controller.attachOfferedImage) {
                        HStack(spacing: 6) {
                            Image(nsImage: offered.thumbnail)
                                .resizable().scaledToFill()
                                .frame(width: 24, height: 24)
                                .clipShape(RoundedRectangle(cornerRadius: 5))
                                .opacity(0.7)
                                .accessibilityHidden(true)
                            Label("Attach clipboard image", systemImage: "plus")
                                .scaledFont(12)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [3]))
                                .foregroundStyle(palette.secondary.opacity(0.6)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Attach the image on the clipboard")
                }
                Button {
                    if let inline = controller.pasteFromClipboard() { session.draft += inline }
                    composerFocused = true
                } label: {
                    Label("Paste", systemImage: "doc.on.clipboard")
                        .scaledFont(12)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(palette.chipFill, in: Capsule())
                }
                .buttonStyle(.plain)
                .help("Add what’s on the clipboard: text, a screenshot or a file (⌘V)")
                .accessibilityLabel("Paste from clipboard")
                Button(action: controller.captureArea) {
                    Label("Capture", systemImage: "camera.viewfinder")
                        .scaledFont(12)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(palette.chipFill, in: Capsule())
                }
                .buttonStyle(.plain)
                .help("Drag over part of the screen to attach it (⌘⇧S)")
                .accessibilityLabel("Capture part of the screen")
                .accessibilityHint("Adds the clipboard’s text, image or file as context")
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
        }
    }

    // MARK: - Transcript

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(session.turns) { turn in
                        TurnView(
                            turn: turn, isLast: turn.id == session.turns.last?.id,
                            canReplace: controller.canReplace, palette: palette,
                            controller: controller
                        )
                        .id(turn.id)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
                    transcriptHeight = $0
                }
            }
            .frame(maxHeight: .infinity)
            .accessibilityLabel("Conversation")
            .onChange(of: session.turns.last?.display) {
                if let last = session.turns.last { proxy.scrollTo(last.id, anchor: .bottom) }
            }
            .onChange(of: session.turns.count) {
                if let last = session.turns.last { proxy.scrollTo(last.id, anchor: .bottom) }
            }
        }
    }

    // MARK: - Composer

    private var placeholder: String {
        if !session.turns.isEmpty { return "Ask a follow-up…" }
        if !session.texts.isEmpty { return "Ask about this, or pick an action below…" }
        if !session.images.isEmpty { return "Ask about the image, or pick an action below…" }
        return "Ask anything, or paste content with ⌘V…"
    }

    private var composer: some View {
        HStack(alignment: .top, spacing: 10) {
            CometMark(size: 19)
                .padding(.top, 2)
            TextField(placeholder, text: Bindable(session).draft, axis: .vertical)
                .textFieldStyle(.plain)
                .scaledFont(17)
                .lineLimit(1...8)
                .focused($composerFocused)
                .onSubmit(submit)
                .onKeyPress(.upArrow) { moveSearch(-1) }
                .onKeyPress(.downArrow) { moveSearch(1) }
                .onKeyPress(.escape) {
                    guard controller.presetQuery != nil else { return .ignored }
                    session.draft = ""
                    return .handled
                }
                .onChange(of: session.draft) { searchIndex = 0 }
                .disabled(session.isRunning)
                .accessibilityLabel("Question")
                .accessibilityHint("Press Return to ask. Command-V pastes text, images or files.")
            if session.isRunning {
                Button(action: controller.stop) {
                    Image(systemName: "stop.circle.fill")
                        .scaledFont(20)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Stop (⌘.)")
                .keyboardShortcut(".", modifiers: .command)
                .accessibilityLabel("Stop response")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func submit() {
        guard let query = controller.presetQuery else {
            controller.send()
            return
        }
        let matches = controller.presetMatches(query)
        guard matches.indices.contains(searchIndex) else { return }
        controller.runFromSearch(matches[searchIndex])
    }

    private func moveSearch(_ offset: Int) -> KeyPress.Result {
        guard let query = controller.presetQuery else { return .ignored }
        let count = controller.presetMatches(query).count
        guard count > 0 else { return .handled }
        searchIndex = (searchIndex + offset + count) % count
        return .handled
    }

    /// `/` plus a few letters filters the presets; ↑ ↓ choose, ↩ runs, Esc clears.
    private func presetSearch(_ query: String) -> some View {
        let matches = Array(controller.presetMatches(query).prefix(7))
        return VStack(alignment: .leading, spacing: 2) {
            if matches.isEmpty {
                Text("No preset matches “\(query)”")
                    .scaledFont(12).foregroundStyle(palette.secondary)
                    .padding(.horizontal, 10).padding(.vertical, 6)
            }
            ForEach(Array(matches.enumerated()), id: \.element.id) { index, preset in
                Button {
                    controller.runFromSearch(preset)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: preset.symbol).frame(width: 18).foregroundStyle(.tint)
                        Text(preset.name).scaledFont(13)
                        Spacer()
                        if let number = controller.presets.index(of: preset.id), number < 9 {
                            Text("⌘\(number + 1)").scaledFont(11).foregroundStyle(.tertiary)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 7)
                            .fill(index == searchIndex ? Color.accentColor.opacity(0.22) : .clear))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(index == searchIndex ? .isSelected : [])
            }
        }
        .padding(6)
        .background(palette.chipFill, in: RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Matching presets")
    }

    private var presetRow: some View {
        HStack(spacing: 0) {
            presetsMenu
                .padding(.leading, 16)
                .padding(.trailing, 4)
            presetChips
        }
        .padding(.bottom, 10)
    }

    /// Every preset in one place, however many there are; the chips beside it only scroll.
    private var presetsMenu: some View {
        Menu {
            ForEach(Array(controller.presets.presets.enumerated()), id: \.element.id) { index, preset in
                Button {
                    controller.run(preset)
                } label: {
                    Label(index < 9 ? "\(preset.name)    ⌘\(index + 1)" : preset.name, systemImage: preset.symbol)
                }
            }
            Divider()
            Button("Search Presets…  /") {
                session.draft = "/"
                composerFocused = true
            }
            Button("Edit Presets…") { controller.editPreset(controller.presets.presets.first?.id ?? UUID()) }
        } label: {
            Label("Presets", systemImage: "square.grid.2x2")
                .scaledFont(12)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .disabled(session.isRunning)
        .help("All presets (type / to search)")
        .accessibilityLabel("All presets")
    }

    private var presetChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(Array(controller.presets.presets.enumerated()), id: \.element.id) {
                    index, preset in
                    PresetChip(preset: preset, index: index, palette: palette) {
                        controller.run(preset)
                    }
                    .disabled(session.isRunning)
                    .contextMenu { presetMenu(preset, index: index) }
                    .accessibilityAction(named: "Move left") {
                        controller.presets.move(id: preset.id, by: -1)
                    }
                    .accessibilityAction(named: "Move right") {
                        controller.presets.move(id: preset.id, by: 1)
                    }
                }
            }
            .padding(.trailing, 16)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Actions")
    }

    @ViewBuilder
    private func presetMenu(_ preset: Preset, index: Int) -> some View {
        let store = controller.presets
        let last = store.presets.count - 1
        Button("Move Left") { store.move(id: preset.id, by: -1) }.disabled(index == 0)
        Button("Move Right") { store.move(id: preset.id, by: 1) }.disabled(index == last)
        Divider()
        Button("Move to Start") { store.moveToStart(id: preset.id) }.disabled(index == 0)
        Button("Move to End") { store.moveToEnd(id: preset.id) }.disabled(index == last)
        Divider()
        Button("Edit “\(preset.name)”…") { controller.editPreset(preset.id) }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 12) {
            ModelMenu(controller: controller)
            if let notice = controller.notice {
                Text(notice)
                    .scaledFont(12)
                    .foregroundStyle(.orange)
                    .lineLimit(2)
                    .accessibilityLabel("Notice: \(notice)")
            }
            Spacer(minLength: 8)
            FooterButton(title: "New", keys: "⌘N", palette: palette, action: controller.startNewChat)
                .keyboardShortcut("n", modifiers: .command)
                .accessibilityLabel("New chat")
            FooterButton(title: "Copy", keys: "⌘⇧C", palette: palette, action: controller.copyLastAnswer)
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .disabled(session.lastAnswer == nil)
                .accessibilityLabel("Copy last answer")
            FooterButton(title: "Settings", keys: "⌘,", palette: palette, action: controller.openSettings)
                .keyboardShortcut(",", modifiers: .command)
        }
        .padding(.leading, 12)
        .padding(.trailing, 28)
        .padding(.vertical, 6)
        .background(palette.footerFill)
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    Task { @MainActor in controller.stageFile(url) }
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) {
                    data, _ in
                    guard let data else { return }
                    Task { @MainActor in controller.attachImageData(data, name: "Image") }
                }
            } else if provider.canLoadObject(ofClass: String.self) {
                _ = provider.loadObject(ofClass: String.self) { string, _ in
                    guard let string else { return }
                    Task { @MainActor in controller.stageDroppedText(string) }
                }
            }
        }
        return true
    }
}

// MARK: - Pieces

private struct TurnView: View {
    let turn: ChatTurn
    let isLast: Bool
    let canReplace: Bool
    let palette: PanelPalette
    let controller: CometController
    @State private var showsDiff = true
    @State private var isEditing = false
    @State private var draft = ""

    var body: some View {
        switch turn.role {
        case .user: user
        case .assistant: assistant
        }
    }

    private var user: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                if let symbol = turn.presetSymbol {
                    Image(systemName: symbol).foregroundStyle(.tint)
                }
                Text(turn.display)
                    .scaledFont(13, weight: .semibold)
                    .textSelection(.enabled)
            }
            if let context = turn.contextPreview {
                Text(context.trimmingCharacters(in: .whitespacesAndNewlines))
                    .scaledFont(12)
                    .foregroundStyle(palette.secondary)
                    .lineLimit(2)
                    .padding(.leading, 8)
                    .overlay(alignment: .leading) {
                        Rectangle().fill(palette.border).frame(width: 2)
                    }
            }
            if !turn.images.isEmpty {
                HStack {
                    ForEach(Array(turn.images.enumerated()), id: \.offset) { _, image in
                        if let thumb = NSImage(data: image.data) {
                            Image(nsImage: thumb)
                                .resizable().scaledToFit()
                                .frame(maxHeight: 56)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(userLabel)
    }

    private var userLabel: String {
        var label = (turn.presetName != nil ? "You ran \(turn.display)" : "You asked: \(turn.display)")
        if turn.contextPreview != nil { label += ", with text attached" }
        if !turn.images.isEmpty { label += ", with \(turn.images.count) image(s)" }
        return label
    }

    @ViewBuilder
    private var assistant: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let error = turn.error {
                VStack(alignment: .leading, spacing: 6) {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .scaledFont(13)
                        .foregroundStyle(.orange)
                        .textSelection(.enabled)
                    if isLast {
                        Button("Retry", action: controller.retry).controlSize(.small)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Error: \(error)")
            } else if turn.display.isEmpty && turn.isStreaming {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(turn.isThinking ? "Thinking…" : "Working…")
                        .foregroundStyle(palette.secondary)
                }
                .scaledFont(13)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(turn.isThinking ? "Thinking" : "Working")
            } else if isEditing {
                TextEditor(text: $draft)
                    .scaledFont(14)
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .frame(minHeight: 90, maxHeight: 260)
                    .background(palette.chipFill, in: RoundedRectangle(cornerRadius: 8))
                    .accessibilityLabel("Edit answer")
                HStack(spacing: 8) {
                    Button("Done") {
                        controller.editAnswer(id: turn.id, text: draft)
                        isEditing = false
                    }
                    .keyboardShortcut(.return, modifiers: .command)
                    Button("Cancel") { isEditing = false }
                }
                .controlSize(.small)
            } else if turn.showsDiff, showsDiff, !turn.isStreaming, let original = turn.original {
                DiffView(original: original, modified: turn.display)
                    .scaledFont(14)
                    .accessibilityLabel("Answer with changes marked")
                    .accessibilityValue(turn.display)
            } else {
                MarkdownView(text: turn.display, midStream: turn.isStreaming)
                    .scaledFont(14)
            }
            if !turn.isStreaming, turn.error == nil, !turn.display.isEmpty, !isEditing {
                actions
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(turn.presetName.map { "\($0) result" } ?? "Answer")
    }

    private var actions: some View {
        HStack(spacing: 8) {
            if isLast && canReplace {
                Button {
                    controller.replace(with: turn)
                } label: {
                    Label("Replace", systemImage: "arrow.uturn.left.circle")
                }
                .keyboardShortcut(.return, modifiers: .command)
                .help("Paste over the original selection (⌘↩)")
                .accessibilityHint("Pastes this answer over the text you selected")
                Button {
                    controller.insertAfter(turn)
                } label: {
                    Label("Insert After", systemImage: "text.append")
                }
                .keyboardShortcut(.return, modifiers: [.command, .shift])
                .help("Keep your text and add the answer after it (⌘⇧↩)")
                .accessibilityHint("Pastes this answer after the text you selected")
            }
            Button {
                controller.copy(turn)
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
            if isLast {
                Button {
                    draft = turn.display
                    isEditing = true
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
                .help("Change the answer before you replace or copy it")
            }
            if turn.showsDiff {
                Toggle("Show changes", isOn: $showsDiff)
                    .toggleStyle(.checkbox)
            }
            if isLast {
                Button {
                    controller.retry()
                } label: {
                    Label("Retry", systemImage: "arrow.clockwise")
                }
            }
        }
        .scaledFont(12)
        .controlSize(.small)
        .buttonStyle(.bordered)
    }
}

private struct ContextChip: View {
    let text: StagedText
    let palette: PanelPalette
    let onRemove: () -> Void

    private var preview: String {
        text.text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: text.symbol).foregroundStyle(palette.secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text(preview).scaledFont(12).lineLimit(1)
                Text("\(text.title) · \(text.text.count) chars")
                    .scaledFont(10)
                    .foregroundStyle(palette.secondary)
            }
            .frame(maxWidth: 320, alignment: .leading)
            RemoveButton(label: "Remove \(text.title.lowercased())", action: onRemove)
        }
        .padding(.leading, 8)
        .padding(.trailing, 2)
        .padding(.vertical, 3)
        .background(palette.chipFill, in: RoundedRectangle(cornerRadius: 8))
        .help(String(text.text.prefix(600)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(text.title), \(text.text.count) characters: \(preview.prefix(200))")
        .accessibilityAction(named: "Remove", onRemove)
    }
}

private struct ImageChip: View {
    let image: StagedImage
    let palette: PanelPalette
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Image(nsImage: image.thumbnail)
                .resizable().scaledToFill()
                .frame(width: 28, height: 28)
                .clipShape(RoundedRectangle(cornerRadius: 5))
            Text(image.name).scaledFont(12).lineLimit(1)
            RemoveButton(label: "Remove image \(image.name)", action: onRemove)
        }
        .padding(.leading, 5)
        .padding(.trailing, 2)
        .padding(.vertical, 3)
        .background(palette.chipFill, in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Image: \(image.name)")
        .accessibilityAction(named: "Remove", onRemove)
    }
}

private struct RemoveButton: View {
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }
}

private struct HeaderIconButton: View {
    let symbol: String
    let label: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .scaledFont(12, weight: .medium)
                .frame(width: 26, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help(help)
        .accessibilityLabel(label)
    }
}

private struct PresetChip: View {
    let preset: Preset
    let index: Int
    let palette: PanelPalette
    let action: () -> Void

    var body: some View {
        let button = Button(action: action) {
            Label(preset.name, systemImage: preset.symbol)
                .scaledFont(12)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(palette.chipFill, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        if index < 9 {
            button
                .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
                .help("\(preset.name) (⌘\(index + 1))")
                .accessibilityHint("Command \(index + 1)")
        } else {
            button.help(preset.name)
        }
    }
}

private struct FooterButton: View {
    let title: String
    let keys: String
    let palette: PanelPalette
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(title)
                Text(keys).foregroundStyle(.tertiary).accessibilityHidden(true)
            }
            .scaledFont(12)
            .padding(.horizontal, 4)
            .frame(minHeight: 24)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(palette.secondary)
        .help("\(title) (\(keys))")
    }
}

/// The corner cue that the panel resizes; the native window edge does the actual resizing.
private struct ResizeGrip: View {
    var body: some View {
        Canvas { context, size in
            for offset in [3.0, 7.0, 11.0] {
                var path = Path()
                path.move(to: CGPoint(x: size.width - offset, y: size.height - 1))
                path.addLine(to: CGPoint(x: size.width - 1, y: size.height - offset))
                context.stroke(path, with: .color(.secondary.opacity(0.55)), lineWidth: 1.2)
            }
        }
        .frame(width: 13, height: 13)
        .padding(7)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct ModelMenu: View {
    let controller: CometController

    var body: some View {
        Menu {
            ForEach(AIBackend.allCases) { backend in
                let status = controller.backends.status(backend)
                Section(backend.title + " — " + status.summary) {
                    ForEach(controller.backends.models(for: backend)) { model in
                        Button {
                            controller.session.model = ModelChoice(backend: backend, model: model.id)
                        } label: {
                            if controller.session.model == ModelChoice(backend: backend, model: model.id) {
                                Label(model.name, systemImage: "checkmark")
                            } else {
                                Text(model.name)
                            }
                        }
                        .disabled(!status.isReady)
                    }
                }
            }
        } label: {
            Text(title).scaledFont(12)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Model for questions")
        .accessibilityLabel("Model: \(title)")
    }

    private var title: String {
        let choice = controller.session.model
        return controller.backends.models(for: choice.backend).first { $0.id == choice.model }?.name
            ?? (choice.model.isEmpty ? choice.backend.title : choice.model)
    }
}
