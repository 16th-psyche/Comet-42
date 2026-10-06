import SwiftUI

/// A plain key, not `@Entry`: the Command Line Tools ship no SwiftUI macro plugin.
private struct UIScaleKey: EnvironmentKey {
    static let defaultValue: CGFloat = 1
}

extension EnvironmentValues {
    /// The reader's text size, 1 being the designed size; every panel font is multiplied by it.
    var uiScale: CGFloat {
        get { self[UIScaleKey.self] }
        set { self[UIScaleKey.self] = newValue }
    }
}

private struct ScaledFont: ViewModifier {
    @Environment(\.uiScale) private var scale
    let size: CGFloat
    let weight: Font.Weight
    let design: Font.Design

    func body(content: Content) -> some View {
        content.font(.system(size: (size * scale).rounded(), weight: weight, design: design))
    }
}

extension View {
    func scaledFont(
        _ size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default
    ) -> some View {
        modifier(ScaledFont(size: size, weight: weight, design: design))
    }
}

/// Colours that firm up under Increase Contrast, so chips and dividers stay visible.
struct PanelPalette {
    let increasedContrast: Bool

    var chipFill: Color { Color.primary.opacity(increasedContrast ? 0.16 : 0.07) }
    var footerFill: Color { Color.primary.opacity(increasedContrast ? 0.10 : 0.04) }
    var secondary: Color { increasedContrast ? Color.primary.opacity(0.8) : Color.secondary }
    var border: Color { Color.primary.opacity(increasedContrast ? 0.5 : 0.12) }
}
