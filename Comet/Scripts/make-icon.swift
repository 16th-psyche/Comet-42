// Renders the Comet app icon to a 1024px PNG. Usage: swift Scripts/make-icon.swift out.png
import AppKit
import CoreGraphics

let size: CGFloat = 1024
let output = CommandLine.arguments.dropFirst().first ?? "AppIcon.png"
let space = CGColorSpace(name: CGColorSpace.displayP3)!
let context = CGContext(
    data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
    space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        colorSpace: space,
        components: [
            CGFloat((hex >> 16) & 0xFF) / 255, CGFloat((hex >> 8) & 0xFF) / 255,
            CGFloat(hex & 0xFF) / 255, alpha
        ])!
}

func gradient(_ stops: [(UInt32, CGFloat, CGFloat)]) -> CGGradient {
    CGGradient(
        colorsSpace: space, colors: stops.map { color($0.0, $0.1) } as CFArray,
        locations: stops.map(\.2))!
}

/// The macOS icon grid: an 824pt continuous-corner squircle centred on a 1024 canvas.
let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
let tilePath = CGPath(roundedRect: tile, cornerWidth: 186, cornerHeight: 186, transform: nil)

// Soft drop shadow under the tile, as Apple's own icons carry.
context.saveGState()
context.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: color(0x000000, 0.4))
context.addPath(tilePath)
context.setFillColor(color(0x0B1033))
context.fillPath()
context.restoreGState()

context.saveGState()
context.addPath(tilePath)
context.clip()

// Night sky: deep navy at the bottom-left, warming to violet where the comet flies.
context.drawLinearGradient(
    gradient([(0x070B26, 1, 0), (0x1A1A5E, 1, 0.5), (0x4B2391, 1, 1)]),
    start: CGPoint(x: tile.minX, y: tile.minY), end: CGPoint(x: tile.maxX, y: tile.maxY),
    options: [])

// A faint nebula behind the head.
context.drawRadialGradient(
    gradient([(0xC86BFA, 0.35, 0), (0xC86BFA, 0, 1)]),
    startCenter: CGPoint(x: 690, y: 690), startRadius: 0,
    endCenter: CGPoint(x: 690, y: 690), endRadius: 420, options: [])

// Stars: fixed, so every build draws the same sky.
let stars: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [
    (215, 800, 5, 0.9), (300, 690, 3, 0.6), (180, 560, 3.5, 0.7), (420, 860, 4, 0.8),
    (560, 790, 2.5, 0.5), (850, 420, 4.5, 0.85), (780, 250, 3, 0.6), (880, 820, 3, 0.55),
    (640, 210, 2.5, 0.5), (240, 330, 2.5, 0.45), (500, 560, 2, 0.4), (860, 600, 2.5, 0.5),
    (360, 470, 2, 0.35), (700, 470, 2, 0.4)
]
for (x, y, r, a) in stars {
    context.setFillColor(color(0xFFFFFF, a))
    context.fillEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
}

// The comet flies up and to the right; its tail streams back toward the lower left.
let head = CGPoint(x: 668, y: 668)
let headRadius: CGFloat = 74

/// A tapered tail from the head's edge to a point, bowed slightly so it reads as motion.
func tail(to end: CGPoint, width: CGFloat, bow: CGFloat) -> CGPath {
    let dx = end.x - head.x
    let dy = end.y - head.y
    let length = (dx * dx + dy * dy).squareRoot()
    let normal = CGPoint(x: -dy / length, y: dx / length)
    let a = CGPoint(x: head.x + normal.x * width, y: head.y + normal.y * width)
    let b = CGPoint(x: head.x - normal.x * width, y: head.y - normal.y * width)
    let mid = CGPoint(x: (head.x + end.x) / 2, y: (head.y + end.y) / 2)
    let path = CGMutablePath()
    path.move(to: a)
    path.addQuadCurve(
        to: end,
        control: CGPoint(x: mid.x + normal.x * (width * 0.55 + bow), y: mid.y + normal.y * (width * 0.55 + bow)))
    path.addQuadCurve(
        to: b,
        control: CGPoint(x: mid.x - normal.x * (width * 0.55 - bow), y: mid.y - normal.y * (width * 0.55 - bow)))
    // Closed straight across the head, where the glow hides the seam.
    path.closeSubpath()
    return path
}

func drawTail(_ path: CGPath, to end: CGPoint, stops: [(UInt32, CGFloat, CGFloat)]) {
    context.saveGState()
    context.addPath(path)
    context.clip()
    context.drawLinearGradient(gradient(stops), start: head, end: end, options: [])
    context.restoreGState()
}

// Outer ion tail (pink-violet), then the main dust tail (cyan to white), then a bright core streak.
let ionEnd = CGPoint(x: 215, y: 330)
drawTail(
    tail(to: ionEnd, width: 72, bow: -60), to: ionEnd,
    stops: [(0xFF8AD8, 0.55, 0), (0xB57BFF, 0.28, 0.45), (0x7B5CFF, 0, 1)])
let dustEnd = CGPoint(x: 250, y: 250)
drawTail(
    tail(to: dustEnd, width: 68, bow: 20), to: dustEnd,
    stops: [(0xFFFFFF, 0.95, 0), (0x8FE9FF, 0.6, 0.35), (0x5AA9FF, 0.18, 0.75), (0x5AA9FF, 0, 1)])
let coreEnd = CGPoint(x: 360, y: 360)
drawTail(
    tail(to: coreEnd, width: 36, bow: 0), to: coreEnd,
    stops: [(0xFFFFFF, 1, 0), (0xFFFFFF, 0.5, 0.5), (0xFFFFFF, 0, 1)])

// Glow around the head, then the head itself.
context.drawRadialGradient(
    gradient([(0xFFFFFF, 0.9, 0), (0xA9F0FF, 0.55, 0.3), (0x8F7BFF, 0, 1)]),
    startCenter: head, startRadius: 0, endCenter: head, endRadius: 230, options: [])
context.setShadow(offset: .zero, blur: 40, color: color(0xFFFFFF, 0.9))
context.setFillColor(color(0xFFFFFF))
context.fillEllipse(
    in: CGRect(x: head.x - headRadius, y: head.y - headRadius, width: headRadius * 2, height: headRadius * 2))
context.setShadow(offset: .zero, blur: 0, color: nil)

// A four-point glint on the head: the "AI" spark.
let glint = CGMutablePath()
let glintRadius: CGFloat = 132
for index in 0..<4 {
    let angle = CGFloat(index) * .pi / 2
    let tip = CGPoint(x: head.x + cos(angle) * glintRadius, y: head.y + sin(angle) * glintRadius)
    let next = CGFloat(index + 1) * .pi / 2
    let nextTip = CGPoint(x: head.x + cos(next) * glintRadius, y: head.y + sin(next) * glintRadius)
    if index == 0 { glint.move(to: tip) }
    glint.addQuadCurve(
        to: nextTip,
        control: CGPoint(x: head.x + (tip.x + nextTip.x - 2 * head.x) * 0.08, y: head.y + (tip.y + nextTip.y - 2 * head.y) * 0.08))
}
glint.closeSubpath()
context.addPath(glint)
context.setFillColor(color(0xFFFFFF, 0.95))
context.fillPath()

// Glassy top sheen.
context.drawLinearGradient(
    gradient([(0xFFFFFF, 0.16, 0), (0xFFFFFF, 0, 1)]),
    start: CGPoint(x: 512, y: tile.maxY), end: CGPoint(x: 512, y: tile.midY + 80), options: [])
context.restoreGState()

// Inner hairline, which keeps the tile crisp on dark backgrounds.
context.addPath(
    CGPath(
        roundedRect: tile.insetBy(dx: 2, dy: 2), cornerWidth: 184, cornerHeight: 184,
        transform: nil))
context.setStrokeColor(color(0xFFFFFF, 0.2))
context.setLineWidth(4)
context.strokePath()

let image = context.makeImage()!
let rep = NSBitmapImageRep(cgImage: image)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
print("Wrote \(output)")
