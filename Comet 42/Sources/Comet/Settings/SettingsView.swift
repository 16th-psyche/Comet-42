import AppKit
import SwiftUI

/// The Settings window: a System Settings–style sidebar of pages.
struct SettingsView: View {
    let controller: CometController
    let hotKeys: HotKeyCenter
    let applyHotKey: () -> Bool

    var body: some View {
        @Bindable var controller = controller
        NavigationSplitView {
            List(SettingsPage.allCases, selection: pageBinding) { page in
                Label {
                    Text(page.title)
                } icon: {
                    IconTile(symbol: page.symbol, color: page.color, size: 22)
                }
                .tag(page)
                .padding(.vertical, 2)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
        } detail: {
            detail(for: SettingsPage(rawValue: controller.settingsTab) ?? .general)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 820, idealWidth: 900, minHeight: 560, idealHeight: 640)
    }

    private var pageBinding: Binding<SettingsPage?> {
        Binding(
            get: { SettingsPage(rawValue: controller.settingsTab) ?? .general },
            set: { controller.settingsTab = ($0 ?? .general).rawValue })
    }

    @ViewBuilder
    private func detail(for page: SettingsPage) -> some View {
        switch page {
        case .general:
            GeneralPage(controller: controller, hotKeys: hotKeys, applyHotKey: applyHotKey)
        case .panel: PanelPage(controller: controller)
        case .models: ModelsPage(controller: controller)
        case .tools: ToolsPage(backends: controller.backends)
        case .presets: PresetsPage(controller: controller, hotKeys: hotKeys)
        case .permissions: PermissionsPage(controller: controller)
        case .about: AboutPage()
        }
    }
}

enum SettingsPage: String, CaseIterable, Identifiable {
    case general
    case panel
    case models
    case tools
    case presets
    case permissions
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .panel: return "Panel"
        case .models: return "Models"
        case .tools: return "AI Tools"
        case .presets: return "Presets"
        case .permissions: return "Permissions"
        case .about: return "About"
        }
    }

    var subtitle: String {
        switch self {
        case .general: return "The shortcut that opens Comet 42, and how it behaves."
        case .panel: return "Text size, where the panel opens, and how to move it."
        case .models: return "Which model answers questions and runs presets."
        case .tools: return "The Claude and Codex command-line tools Comet 42 runs on."
        case .presets: return "One-click actions. The first nine get ⌘1–⌘9."
        case .permissions: return "What Comet 42 needs from macOS, and why."
        case .about: return "Version and credits."
        }
    }

    var symbol: String {
        switch self {
        case .general: return "gearshape.fill"
        case .panel: return "macwindow"
        case .models: return "cpu.fill"
        case .tools: return "terminal.fill"
        case .presets: return "wand.and.sparkles"
        case .permissions: return "hand.raised.fill"
        case .about: return "info.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .general: return .gray
        case .panel: return .blue
        case .models: return .purple
        case .tools: return .black
        case .presets: return .pink
        case .permissions: return .orange
        case .about: return .indigo
        }
    }
}

// MARK: - Shared pieces

private struct PageHeader: View {
    let page: SettingsPage

    var body: some View {
        HStack(spacing: 14) {
            IconTile(symbol: page.symbol, color: page.color, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(page.title).font(.title2.weight(.semibold))
                Text(page.subtitle).font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 4)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// A page: its header, then a grouped form.
private struct SettingsForm<Content: View>: View {
    let page: SettingsPage
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(page: page)
            Form { content }
                .formStyle(.grouped)
                .scrollContentBackground(.hidden)
        }
    }
}

// MARK: - General

private struct GeneralPage: View {
    let controller: CometController
    let hotKeys: HotKeyCenter
    let applyHotKey: () -> Bool
    @State private var hotKeyFailed = false
    @State private var launchesAtLogin = LaunchAtLogin.isEnabled
    @State private var loginError: String?
    @State private var confirmsClear = false

    private var settings: AppSettings { controller.settings }

    var body: some View {
        @Bindable var settings = settings
        SettingsForm(page: .general) {
            Section {
                LabeledContent {
                    HotKeyRecorder(chord: settings.hotKey, hotKeys: hotKeys) { chord in
                        settings.hotKey = chord
                        hotKeyFailed = !applyHotKey()
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Open Comet 42")
                        Text("Works in any app. Select text or copy a screenshot first.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                if hotKeyFailed {
                    Label(
                        "Another app already uses that shortcut. Pick a different one.",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.callout).foregroundStyle(.orange)
                } else if isBareShift(settings.hotKey) {
                    Label(
                        "Shift + a key also blocks typing that character with Shift in every app.",
                        systemImage: "exclamationmark.triangle"
                    )
                    .font(.callout).foregroundStyle(.orange)
                }
            } header: {
                Text("Shortcut")
            }

            Section("Startup") {
                DescribedToggle(
                    title: "Open at login",
                    detail: "Starts Comet 42 in the menu bar when you log in, so the shortcut always works.",
                    isOn: $launchesAtLogin)
                .onChange(of: launchesAtLogin) {
                    loginError = LaunchAtLogin.set(launchesAtLogin)
                    if loginError != nil { launchesAtLogin = LaunchAtLogin.isEnabled }
                }
                if let loginError {
                    Text(loginError).font(.caption).foregroundStyle(.orange)
                }
            }

            Section("Behaviour") {
                DescribedToggle(
                    title: "Hide the panel when you click elsewhere",
                    detail: "Turn off to keep it open, like the pin button in the panel.",
                    isOn: $settings.hidesOnFocusLoss)
                DescribedToggle(
                    title: "Attach fresh screenshots automatically",
                    detail: "A picture copied in the last 2 minutes is attached when you open the panel. "
                        + "Older ones are offered as a chip.",
                    isOn: $settings.autoAttachClipboardImage)
            }

            Section {
                DescribedToggle(
                    title: "Keep chat history",
                    detail: "Saves your last \(ChatHistoryStore.limit) chats on this Mac (text only, never images). Open them with History (⌘Y) in the panel.",
                    isOn: $settings.keepsHistory)
                LabeledContent {
                    Button("Clear History…") { confirmsClear = true }
                        .disabled(controller.history.chats.isEmpty)
                } label: {
                    Text(controller.history.chats.isEmpty
                        ? "No saved chats"
                        : "\(controller.history.chats.count) saved chat\(controller.history.chats.count == 1 ? "" : "s")")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("History")
            }
            .confirmationDialog("Delete all saved chats?", isPresented: $confirmsClear) {
                Button("Clear History", role: .destructive) { controller.history.clear() }
            } message: {
                Text("This can’t be undone.")
            }

            Section("In the panel") {
                ShortcutTip(keys: ["↩"], text: "Ask")
                ShortcutTip(keys: ["⌘", "1–9"], text: "Run a preset")
                ShortcutTip(keys: ["⌘", "V"], text: "Paste text, a screenshot or a file")
                ShortcutTip(keys: ["⌘", "↩"], text: "Replace the selection with the answer")
                ShortcutTip(keys: ["⌘", "⇧", "C"], text: "Copy the last answer")
                ShortcutTip(keys: ["⌘", "N"], text: "New chat")
                ShortcutTip(keys: ["esc"], text: "Close")
            }
        }
    }

    private func isBareShift(_ chord: HotKeyChord) -> Bool {
        chord.modifiers == UInt32(512)  // shiftKey alone
    }
}

// MARK: - Panel

private struct PanelPage: View {
    let controller: CometController
    private var settings: AppSettings { controller.settings }

    var body: some View {
        @Bindable var settings = settings
        let percent = Int((settings.textScale * 100).rounded())
        SettingsForm(page: .panel) {
            Section("Text size") {
                HStack(spacing: 10) {
                    Image(systemName: "textformat.size.smaller").accessibilityHidden(true)
                    Slider(value: $settings.textScale, in: AppSettings.textScaleRange, step: 0.05)
                        .accessibilityLabel("Text size")
                        .accessibilityValue("\(percent) percent")
                    Image(systemName: "textformat.size.larger").accessibilityHidden(true)
                    Text("\(percent)%")
                        .monospacedDigit()
                        .frame(width: 44, alignment: .trailing)
                    Button("Reset") { settings.textScale = 1 }
                        .disabled(settings.textScale == 1)
                }
                Text("Fix spelling, then paste it back.")
                    .font(.system(size: (15 * settings.textScale).rounded()))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
                    .accessibilityLabel("Preview of the panel text size")
            }

            Section("Position") {
                DescribedToggle(
                    title: "Open where I last left it",
                    detail: "Off opens the panel near the top of the screen with the pointer.",
                    isOn: $settings.remembersPanelPosition)
                LabeledContent {
                    Button("Reset Size and Position") { controller.resetPanelGeometry() }
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Size and position")
                        Text("\(Int(settings.panelWidth)) pt wide, grows up to \(Int(settings.panelMaxHeight)) pt tall")
                            .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    }
                }
            }

            Section("Moving and resizing") {
                ShortcutTip(keys: ["drag title bar"], text: "Move the panel")
                ShortcutTip(keys: ["drag an edge"], text: "Resize it")
                ShortcutTip(keys: ["⌘", "+"], text: "Larger text")
                ShortcutTip(keys: ["⌘", "−"], text: "Smaller text")
                ShortcutTip(keys: ["⌘", "0"], text: "Actual text size")
                ShortcutTip(keys: ["⌘", "⌥", "0"], text: "Reset size and position")
            }
        }
    }
}

// MARK: - Models

private struct ModelsPage: View {
    let controller: CometController
    @State private var codexModelsText = ""
    private var settings: AppSettings { controller.settings }

    var body: some View {
        @Bindable var settings = settings
        SettingsForm(page: .models) {
            Section {
                ModelPicker(
                    title: "Questions", detail: "Free-form questions and follow-ups",
                    choice: $settings.chatModel, backends: controller.backends)
                ModelPicker(
                    title: "Presets", detail: "A preset can override this in its own settings",
                    choice: $settings.actionModel, backends: controller.backends)
            } header: {
                Text("Default models")
            } footer: {
                Text("A faster model (such as Haiku) keeps presets snappy; a larger one answers harder questions.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Reasoning effort") {
                Picker("Effort", selection: $settings.effort) {
                    Text("Default").tag("")
                    ForEach(["low", "medium", "high", "xhigh"], id: \.self) {
                        Text($0 == "xhigh" ? "Max" : $0.capitalized).tag($0)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                Text("Higher effort thinks longer before answering. Default leaves it to the CLI.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Codex") {
                TextField("Extra models", text: $codexModelsText, prompt: Text("gpt-5.5, o4-mini"))
                    .onSubmit(save)
                    .onChange(of: codexModelsText) { save() }
                Text("Codex doesn’t publish a model list. Add names here, separated by commas, to pick them.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .onAppear { codexModelsText = settings.codexModels.joined(separator: ", ") }
    }

    private func save() {
        let models = codexModelsText.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        settings.codexModels = models
        controller.backends.codexModels = models
    }
}

private struct ModelPicker: View {
    let title: String
    let detail: String
    @Binding var choice: ModelChoice
    let backends: AIBackends

    var body: some View {
        Picker(selection: $choice) {
            ForEach(AIBackend.allCases) { backend in
                Section(backend.title) {
                    ForEach(options(for: backend), id: \.self) { option in
                        Text(name(of: option)).tag(option)
                    }
                }
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    /// The current choice stays listed even before the CLI has reported its catalog.
    private func options(for backend: AIBackend) -> [ModelChoice] {
        var result = backends.models(for: backend).map { ModelChoice(backend: backend, model: $0.id) }
        if choice.backend == backend, !result.contains(choice) { result.insert(choice, at: 0) }
        return result
    }

    private func name(of option: ModelChoice) -> String {
        backends.models(for: option.backend).first { $0.id == option.model }?.name
            ?? (option.model.isEmpty ? option.backend.title + " Default" : option.model)
    }
}

// MARK: - AI tools

private struct ToolsPage: View {
    let backends: AIBackends

    var body: some View {
        SettingsForm(page: .tools) {
            ForEach(AIBackend.allCases) { backend in
                Section {
                    ToolCard(backend: backend, status: backends.status(backend))
                }
            }
            Section {
                HStack {
                    Text("No API keys are stored in Comet 42. Each tool uses its own sign-in.")
                        .font(.callout).foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        backends.refresh()
                    } label: {
                        Label("Check Again", systemImage: "arrow.clockwise")
                    }
                }
            }
        }
    }
}

// MARK: - Presets

private struct PresetsPage: View {
    let controller: CometController
    let hotKeys: HotKeyCenter
    @State private var selection: UUID?
    @State private var confirmsRestore = false

    private var store: PresetStore { controller.presets }

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(page: .presets)
            HStack(spacing: 0) {
                presetList
                    .frame(width: 290)
                Divider()
                editor
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(Color.primary.opacity(0.025))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.1)))
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .onAppear {
            takeRequestedPreset()
            if selection == nil { selection = store.presets.first?.id }
        }
        .onChange(of: controller.presetToEdit) { takeRequestedPreset() }
        .confirmationDialog(
            "Replace all presets with the built-in set?", isPresented: $confirmsRestore
        ) {
            Button("Restore Defaults", role: .destructive) {
                store.restoreDefaults()
                selection = store.presets.first?.id
            }
        } message: {
            Text("Your edits, added presets and order will be lost.")
        }
    }

    private var presetList: some View {
        VStack(spacing: 0) {
            List(selection: $selection) {
                ForEach(Array(store.presets.enumerated()), id: \.element.id) { index, preset in
                    HStack(spacing: 8) {
                        IconTile(symbol: preset.symbol, color: tint(for: preset), size: 22)
                        Text(preset.name).lineLimit(1)
                        Spacer(minLength: 4)
                        if index < 9 {
                            Text("⌘\(index + 1)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                    .tag(preset.id)
                    .contextMenu { rowMenu(preset) }
                    .accessibilityElement(children: .combine)
                    .accessibilityHint(index < 9 ? "Shortcut Command \(index + 1)" : "")
                    .accessibilityAction(named: "Move up") { store.move(id: preset.id, by: -1) }
                    .accessibilityAction(named: "Move down") { store.move(id: preset.id, by: 1) }
                }
                .onMove { store.move(fromOffsets: $0, toOffset: $1) }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            Divider()
            HStack(spacing: 2) {
                BarButton(symbol: "plus", label: "Add preset") { add() }
                BarButton(symbol: "minus", label: "Delete preset") { delete() }
                    .disabled(selection == nil)
                BarButton(symbol: "plus.square.on.square", label: "Duplicate preset") { duplicate() }
                    .disabled(selection == nil)
                Divider().frame(height: 16).padding(.horizontal, 4)
                BarButton(symbol: "arrow.up", label: "Move preset up (⌥⌘↑)") {
                    if let selection { store.move(id: selection, by: -1) }
                }
                .disabled(selection == nil || selection.flatMap(store.index(of:)) == 0)
                .keyboardShortcut(.upArrow, modifiers: [.command, .option])
                BarButton(symbol: "arrow.down", label: "Move preset down (⌥⌘↓)") {
                    if let selection { store.move(id: selection, by: 1) }
                }
                .disabled(
                    selection == nil
                        || selection.flatMap(store.index(of:)) == store.presets.count - 1)
                .keyboardShortcut(.downArrow, modifiers: [.command, .option])
                Spacer()
                Menu {
                    Button("Restore Defaults…") { confirmsRestore = true }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("More")
                .accessibilityLabel("More preset actions")
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
    }

    @ViewBuilder
    private var editor: some View {
        if let selection, let preset = store.preset(id: selection) {
            PresetEditor(
                preset: preset, index: store.index(of: selection) ?? 0,
                tint: tint(for: preset), backends: controller.backends, hotKeys: hotKeys,
                takenShortcuts: takenShortcuts(except: selection)
            ) { store.upsert($0) }
            .id(selection)
        } else {
            VStack(spacing: 10) {
                Image(systemName: "wand.and.sparkles")
                    .font(.system(size: 34)).foregroundStyle(.tertiary)
                Text("Select a preset to edit it").font(.headline)
                Text("Reorder by dragging, with ↑ ↓ below, or ⌥⌘↑ / ⌥⌘↓.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func rowMenu(_ preset: Preset) -> some View {
        Button("Move Up") { store.move(id: preset.id, by: -1) }
        Button("Move Down") { store.move(id: preset.id, by: 1) }
        Divider()
        Button("Move to Top") { store.moveToStart(id: preset.id) }
        Button("Move to Bottom") { store.moveToEnd(id: preset.id) }
        Divider()
        Button("Duplicate") {
            selection = preset.id
            duplicate()
        }
        Button("Delete", role: .destructive) {
            selection = preset.id
            delete()
        }
    }

    /// Every shortcut already in use, so a preset cannot take one that would never fire.
    private func takenShortcuts(except id: UUID) -> [HotKeyChord: String] {
        var taken = [controller.settings.hotKey: "Open Comet 42"]
        for preset in store.presets where preset.id != id {
            if let chord = preset.hotKey { taken[chord] = preset.name }
        }
        return taken
    }

    private func tint(for preset: Preset) -> Color {
        preset.transformsText ? .pink : .indigo
    }

    private func add() {
        let preset = Preset(
            name: "New Preset", symbol: "sparkles",
            instructions: "Describe what to do with the text.")
        store.upsert(preset)
        selection = preset.id
    }

    private func duplicate() {
        guard let selection, let original = store.preset(id: selection) else { return }
        var copy = original
        copy.id = UUID()
        copy.name = original.name + " Copy"
        store.upsert(copy)
        if let from = store.index(of: copy.id), let to = store.index(of: original.id) {
            store.move(fromOffsets: IndexSet(integer: from), toOffset: to + 1)
        }
        self.selection = copy.id
    }

    private func delete() {
        guard let selection, let index = store.index(of: selection) else { return }
        store.delete(id: selection)
        let next = min(index, store.presets.count - 1)
        self.selection = next >= 0 ? store.presets[next].id : nil
    }

    private func takeRequestedPreset() {
        guard let id = controller.presetToEdit else { return }
        selection = id
        controller.presetToEdit = nil
    }
}

private struct BarButton: View {
    let symbol: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .frame(width: 24, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help(label)
        .accessibilityLabel(label)
    }
}

private struct PresetEditor: View {
    @State var preset: Preset
    let index: Int
    let tint: Color
    let backends: AIBackends
    let hotKeys: HotKeyCenter
    let takenShortcuts: [HotKeyChord: String]
    let onSave: (Preset) -> Void
    @State private var showsSymbols = false
    @State private var shortcutClash: String?

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    Button {
                        showsSymbols = true
                    } label: {
                        IconTile(symbol: preset.symbol, color: tint, size: 44)
                    }
                    .buttonStyle(.plain)
                    .help("Choose an icon")
                    .accessibilityLabel("Icon: \(preset.symbol). Choose an icon")
                    .popover(isPresented: $showsSymbols, arrowEdge: .bottom) {
                        SymbolPicker(selection: $preset.symbol) { showsSymbols = false }
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        TextField("Name", text: $preset.name, prompt: Text("Preset name"))
                            .textFieldStyle(.plain)
                            .font(.title3.weight(.semibold))
                            .labelsHidden()
                            .accessibilityLabel("Preset name")
                        Text(index < 9 ? "⌘\(index + 1) in the panel" : "No shortcut (move it into the first nine)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            Section {
                TextEditor(text: $preset.instructions)
                    .font(.system(size: 12.5))
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 170)
                    .accessibilityLabel("Instructions")
            } header: {
                HStack {
                    Text("Instructions")
                    Spacer()
                    Text("\(preset.instructions.count) characters")
                        .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                }
            } footer: {
                Text("Tell the model what to do with the selected text, pasted text or screenshot.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                LabeledContent {
                    HStack(spacing: 6) {
                        HotKeyRecorder(chord: preset.hotKey, hotKeys: hotKeys) { chord in
                            if let owner = takenShortcuts[chord] {
                                shortcutClash = "\(chord.displayString) is already used by \(owner)."
                            } else {
                                shortcutClash = nil
                                preset.hotKey = chord
                            }
                        }
                        if preset.hotKey != nil {
                            Button {
                                preset.hotKey = nil
                                shortcutClash = nil
                            } label: {
                                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("Remove shortcut")
                            .accessibilityLabel("Remove shortcut")
                        }
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Run from any app")
                        Text("Select text anywhere and press it. No panel opens if the result replaces the selection directly.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                if let shortcutClash {
                    Label(shortcutClash, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout).foregroundStyle(.orange)
                }
            } header: {
                Text("Shortcut")
            }

            Section("Behaviour") {
                DescribedToggle(
                    title: "Rewrites the text",
                    detail: "Returns only the new text, so it can replace your selection. "
                        + "Turn off for explanations and summaries.",
                    isOn: $preset.transformsText)
                Picker("When it finishes", selection: $preset.delivery) {
                    ForEach(Preset.Delivery.allCases) { Text($0.title).tag($0) }
                }
                .disabled(!preset.transformsText)
                Toggle("Highlight what changed", isOn: $preset.showsDiff)
                    .disabled(!preset.transformsText)
                Picker("Model", selection: $preset.model) {
                    Text("Default preset model").tag(ModelChoice?.none)
                    ForEach(AIBackend.allCases) { backend in
                        Section(backend.title) {
                            ForEach(backends.models(for: backend)) { model in
                                Text(model.name)
                                    .tag(ModelChoice?.some(ModelChoice(backend: backend, model: model.id)))
                            }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .onChange(of: preset) { onSave(preset) }
    }
}

/// A grid of fitting SF Symbols, plus a field for any other symbol name.
private struct SymbolPicker: View {
    @Binding var selection: String
    let onDone: () -> Void
    @State private var custom = ""

    private static let symbols = [
        "wand.and.sparkles", "sparkles", "textformat.abc", "textformat", "pencil", "pencil.line",
        "highlighter", "text.quote", "text.alignleft", "text.line.3.summary", "list.bullet",
        "list.number", "tablecells", "envelope", "paperplane", "bubble.left", "bubble.left.and.text.bubble.right",
        "quote.bubble", "lightbulb", "graduationcap", "book", "magnifyingglass", "translate",
        "globe", "briefcase", "face.smiling", "heart", "hand.thumbsup", "star", "bolt",
        "arrow.down.right.and.arrow.up.left", "arrow.up.left.and.arrow.down.right", "scissors",
        "checkmark.seal", "exclamationmark.bubble", "questionmark.circle", "doc.text",
        "doc.text.magnifyingglass", "text.viewfinder", "photo", "chart.bar", "number",
        "chevron.left.forwardslash.chevron.right", "terminal", "calendar", "clock", "person",
        "person.2", "megaphone", "tag"
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(32), spacing: 6), count: 8), spacing: 6) {
                ForEach(Self.symbols, id: \.self) { symbol in
                    Button {
                        selection = symbol
                        onDone()
                    } label: {
                        Image(systemName: symbol)
                            .font(.system(size: 15))
                            .frame(width: 32, height: 32)
                            .background(
                                RoundedRectangle(cornerRadius: 7).fill(
                                    selection == symbol ? Color.accentColor.opacity(0.25) : Color.primary.opacity(0.05)))
                    }
                    .buttonStyle(.plain)
                    .help(symbol)
                    .accessibilityLabel(symbol)
                }
            }
            HStack {
                TextField("Other SF Symbol name", text: $custom)
                    .onSubmit(applyCustom)
                Button("Use", action: applyCustom)
                    .disabled(NSImage(systemSymbolName: custom, accessibilityDescription: nil) == nil)
            }
        }
        .padding(14)
        .frame(width: 330)
    }

    private func applyCustom() {
        guard NSImage(systemSymbolName: custom, accessibilityDescription: nil) != nil else { return }
        selection = custom
        onDone()
    }
}

// MARK: - Permissions

private struct PermissionsPage: View {
    let controller: CometController

    var body: some View {
        SettingsForm(page: .permissions) {
            Section {
                HStack(alignment: .top, spacing: 12) {
                    IconTile(symbol: "accessibility", color: .blue, size: 34)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Accessibility").font(.headline)
                            Spacer()
                            if controller.accessibilityTrusted {
                                StatusBadge(text: "Allowed", color: .green)
                            } else {
                                StatusBadge(text: "Not allowed", color: .orange)
                            }
                        }
                        Text(
                            "Lets Comet 42 read the text you select in other apps and paste results back. "
                                + "Nothing is read until you press the shortcut.")
                            .font(.callout).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        if !controller.accessibilityTrusted {
                            Button("Open Accessibility Settings") {
                                Permissions.ensureAccessibility()
                                Permissions.openAccessibilitySettings()
                            }
                            .padding(.top, 4)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            Section {
                HStack(alignment: .top, spacing: 12) {
                    IconTile(symbol: "doc.on.clipboard", color: .gray, size: 34)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Clipboard").font(.headline)
                        Text(
                            "Comet 42 watches only when the clipboard changes, so it can offer a fresh "
                                + "screenshot. When it borrows the clipboard to copy or paste, it puts your "
                                + "content back afterwards.")
                            .font(.callout).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }
}

// MARK: - About

private struct AboutPage: View {
    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    var body: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 112, height: 112)
                .accessibilityHidden(true)
            Text("Comet 42").font(.largeTitle.weight(.semibold))
            Text("Version \(version)").foregroundStyle(.secondary)
            Text("Ask about selected text, pasted content or screenshots, using your Claude or Codex CLI.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 380)
            HStack(spacing: 10) {
                Button("Show Presets File") {
                    let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                        .appending(path: "Comet/presets.json")
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
            }
            .padding(.top, 6)
            Spacer()
            Text("Open source under the GNU AGPL-3.0")
                .font(.caption).foregroundStyle(.tertiary)
                .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity)
    }
}
