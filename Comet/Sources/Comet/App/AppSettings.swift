import Carbon.HIToolbox
import Foundation
import Observation

/// A chord as Carbon registers it: a virtual key code and Carbon modifier bits.
nonisolated struct HotKeyChord: Codable, Equatable, Sendable {
    var keyCode: UInt32
    var modifiers: UInt32

    static let `default` = HotKeyChord(keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey))
}

/// Every preference, persisted as one JSON blob in `UserDefaults`.
@Observable
final class AppSettings {
    private struct Stored: Codable {
        var hotKey: HotKeyChord = .default
        var chatModel: ModelChoice = .default
        var actionModel: ModelChoice = ModelChoice(backend: .claude, model: "haiku")
        var effort: String = ""
        var codexModels: [String] = []
        var autoAttachClipboardImage = true
        var hidesOnFocusLoss = true
        var panelWidth: Double = 660
        var panelMaxHeight: Double = 600
        var panelTopLeft: [Double]?
        var remembersPanelPosition = true
        var textScale: Double = 1

        init() {}

        /// Every field optional on the way in, so a settings blob from an older build still loads.
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let d = Stored()
            hotKey = try c.decodeIfPresent(HotKeyChord.self, forKey: .hotKey) ?? d.hotKey
            chatModel = try c.decodeIfPresent(ModelChoice.self, forKey: .chatModel) ?? d.chatModel
            actionModel = try c.decodeIfPresent(ModelChoice.self, forKey: .actionModel) ?? d.actionModel
            effort = try c.decodeIfPresent(String.self, forKey: .effort) ?? d.effort
            codexModels = try c.decodeIfPresent([String].self, forKey: .codexModels) ?? d.codexModels
            autoAttachClipboardImage =
                try c.decodeIfPresent(Bool.self, forKey: .autoAttachClipboardImage)
                ?? d.autoAttachClipboardImage
            hidesOnFocusLoss =
                try c.decodeIfPresent(Bool.self, forKey: .hidesOnFocusLoss) ?? d.hidesOnFocusLoss
            panelWidth = try c.decodeIfPresent(Double.self, forKey: .panelWidth) ?? d.panelWidth
            panelMaxHeight =
                try c.decodeIfPresent(Double.self, forKey: .panelMaxHeight) ?? d.panelMaxHeight
            panelTopLeft = try c.decodeIfPresent([Double].self, forKey: .panelTopLeft)
            remembersPanelPosition =
                try c.decodeIfPresent(Bool.self, forKey: .remembersPanelPosition)
                ?? d.remembersPanelPosition
            textScale = try c.decodeIfPresent(Double.self, forKey: .textScale) ?? d.textScale
        }
    }

    private static let key = "CometSettings"

    var hotKey: HotKeyChord { didSet { save() } }
    var chatModel: ModelChoice { didSet { save() } }
    var actionModel: ModelChoice { didSet { save() } }
    /// Empty leaves reasoning effort to the CLI.
    var effort: String { didSet { save() } }
    var codexModels: [String] { didSet { save() } }
    /// A picture copied in the last few minutes is attached on summon; an older one is offered.
    var autoAttachClipboardImage: Bool { didSet { save() } }
    var hidesOnFocusLoss: Bool { didSet { save() } }
    var panelWidth: Double { didSet { save() } }
    /// The tallest the panel grows to show a long chat; set by dragging its bottom edge.
    var panelMaxHeight: Double { didSet { save() } }
    var panelTopLeft: [Double]? { didSet { save() } }
    var remembersPanelPosition: Bool { didSet { save() } }
    var textScale: Double { didSet { save() } }

    static let textScaleRange: ClosedRange<Double> = 0.85...1.6
    static let defaultPanelWidth: Double = 660
    static let defaultPanelMaxHeight: Double = 600

    init() {
        let stored =
            UserDefaults.standard.data(forKey: Self.key)
            .flatMap { try? JSONDecoder().decode(Stored.self, from: $0) } ?? Stored()
        hotKey = stored.hotKey
        chatModel = stored.chatModel
        actionModel = stored.actionModel
        effort = stored.effort
        codexModels = stored.codexModels
        autoAttachClipboardImage = stored.autoAttachClipboardImage
        hidesOnFocusLoss = stored.hidesOnFocusLoss
        panelWidth = stored.panelWidth
        panelMaxHeight = stored.panelMaxHeight
        panelTopLeft = stored.panelTopLeft
        remembersPanelPosition = stored.remembersPanelPosition
        textScale = stored.textScale
    }

    func stepTextScale(by delta: Double) {
        let next = ((textScale + delta) * 20).rounded() / 20
        textScale = min(max(next, Self.textScaleRange.lowerBound), Self.textScaleRange.upperBound)
    }

    var effortValue: String? { effort.isEmpty ? nil : effort }

    private func save() {
        var stored = Stored()
        stored.hotKey = hotKey
        stored.chatModel = chatModel
        stored.actionModel = actionModel
        stored.effort = effort
        stored.codexModels = codexModels
        stored.autoAttachClipboardImage = autoAttachClipboardImage
        stored.hidesOnFocusLoss = hidesOnFocusLoss
        stored.panelWidth = panelWidth
        stored.panelMaxHeight = panelMaxHeight
        stored.panelTopLeft = panelTopLeft
        stored.remembersPanelPosition = remembersPanelPosition
        stored.textScale = textScale
        guard let data = try? JSONEncoder().encode(stored) else { return }
        UserDefaults.standard.set(data, forKey: Self.key)
    }
}
