// The background of the installer window: a calm surface, the product's own curved arrow from
// the app to Applications, and one line of instruction. Drawn at 2x for a 660 by 400 window.
import AppKit
@testable import ShotputKit

func installerBackground(to path: String) {
    let scale: CGFloat = 2
    let size = CGSize(width: 660, height: 400)
    let base = bitmap(width: Int(size.width * scale), height: Int(size.height * scale)) { ctx in
        ctx.scaleBy(x: scale, y: scale)
        ctx.setFillColor(rgb(0xF4F2EE))
        ctx.fill(CGRect(origin: .zero, size: size))
        // A faint lift behind the two icons, so they sit on something without a box around them.
        let glow = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                              colors: [rgb(0xFFFFFF, 0.9), rgb(0xFFFFFF, 0)] as CFArray, locations: [0, 1])!
        for x in [165.0, 495.0] {
            ctx.drawRadialGradient(glow, startCenter: CGPoint(x: x, y: 200), startRadius: 0,
                                   endCenter: CGPoint(x: x, y: 200), endRadius: 120, options: [])
        }

        let text = NSAttributedString(string: "Drag Shotput into Applications", attributes: [
            .font: NSFont.systemFont(ofSize: 15, weight: .medium),
            .foregroundColor: NSColor(hex: 0x736F67),
        ])
        let line = CTLineCreateWithAttributedString(text)
        let width = CTLineGetTypographicBounds(line, nil, nil, nil)
        ctx.textPosition = CGPoint(x: (size.width - width) / 2, y: 58)
        CTLineDraw(line, ctx)
    }

    // Finder places icons from the top-left, so the arrow is laid out the same way.
    let arrow = Annotation(kind: .arrow(from: CGPoint(x: 252, y: 178), to: CGPoint(x: 404, y: 178)), color: .blue, weight: .regular)
        .bent(through: CGPoint(x: 328, y: 150))
    guard let out = AnnotationRenderer().flatten(base: base, scale: scale, annotations: [arrow], outputScale: scale) else {
        fatalError("flatten failed")
    }
    write(out, scale: scale, to: path)
}
