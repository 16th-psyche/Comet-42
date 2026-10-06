import AppKit
import SwiftUI

/// The comet mark: a round head flying to the upper right, a tapered tail and two streaks.
nonisolated struct CometGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        let origin = CGPoint(x: rect.midX - side / 2, y: rect.midY - side / 2)
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: origin.x + x * side, y: origin.y + y * side)
        }

        let head = point(0.72, 0.28)
        let radius = 0.2 * side
        let tip = point(0.05, 0.95)
        let dx = tip.x - head.x
        let dy = tip.y - head.y
        let length = (dx * dx + dy * dy).squareRoot()
        let along = CGPoint(x: dx / length, y: dy / length)
        let across = CGPoint(x: -along.y, y: along.x)

        func offset(_ base: CGPoint, across a: CGFloat, along b: CGFloat) -> CGPoint {
            CGPoint(x: base.x + across.x * a + along.x * b, y: base.y + across.y * a + along.y * b)
        }

        /// A wedge from a base of half-width `width` to a point, bowed slightly outward.
        func wedge(_ path: inout Path, from start: CGPoint, width: CGFloat, to end: CGPoint) {
            let mid = CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
            path.move(to: offset(start, across: width, along: 0))
            path.addQuadCurve(to: end, control: offset(mid, across: width * 0.45, along: 0))
            path.addQuadCurve(
                to: offset(start, across: -width, along: 0),
                control: offset(mid, across: -width * 0.45, along: 0))
            path.closeSubpath()
        }

        var path = Path()
        path.addEllipse(
            in: CGRect(x: head.x - radius, y: head.y - radius, width: radius * 2, height: radius * 2))
        wedge(&path, from: head, width: radius * 0.86, to: tip)
        let gap = radius * 1.45
        wedge(
            &path, from: offset(head, across: gap, along: radius * 0.35), width: side * 0.045,
            to: offset(head, across: gap, along: length * 0.62))
        wedge(
            &path, from: offset(head, across: -gap, along: radius * 0.35), width: side * 0.045,
            to: offset(head, across: -gap, along: length * 0.5))
        return path
    }

    /// The menu-bar icon: a template image, so macOS tints it for light and dark menu bars.
    @MainActor
    static func menuBarImage(size: CGFloat = 18) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: true) { rect in
            let path = CometGlyph().path(in: rect.insetBy(dx: 1, dy: 1)).cgPath
            NSColor.black.setFill()
            NSBezierPath(cgPath: path).fill()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Comet 42"
        return image
    }
}

/// The glyph in the app icon's colours, sized with the panel's text scale.
struct CometMark: View {
    let size: CGFloat
    @Environment(\.uiScale) private var scale

    var body: some View {
        CometGlyph()
            .fill(
                LinearGradient(
                    colors: [Color(red: 0.62, green: 0.93, blue: 1), Color(red: 0.6, green: 0.45, blue: 1)],
                    startPoint: .topTrailing, endPoint: .bottomLeading)
            )
            .frame(width: (size * scale).rounded(), height: (size * scale).rounded())
            .accessibilityHidden(true)
    }
}
