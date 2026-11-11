// Development helper.
//   shotput-dev preview out.png   every annotation kind over light and dark backdrops
//   shotput-dev icon out.png      the 1024pt app icon, drawn with the product's own renderer
//   shotput-dev editor out.png    offscreen editor checks, plus a render of the window
//   shotput-dev overlay out.png   offscreen selection-overlay checks, plus renders
//   shotput-dev settings out.png  renders every Settings tab and welcome step, checks they fit
//   shotput-dev installer out.png the installer window background, 660 by 400 at 2x
import AppKit
import ShotputKit

func bitmap(width: Int, height: Int, _ draw: (CGContext) -> Void) -> CGImage {
    let ctx = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    draw(ctx)
    return ctx.makeImage()!
}

func rgb(_ hex: UInt, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255, alpha: alpha
    )
}

func write(_ image: CGImage, scale: CGFloat, to path: String) {
    guard let data = ImageCoding.pngData(image, scale: scale) else { fatalError("PNG encoding failed") }
    try! data.write(to: URL(fileURLWithPath: path))
    print("wrote \(path) (\(image.width)x\(image.height))")
}

func preview(to path: String) {
    let scale: CGFloat = 2
    let size = CGSize(width: 760, height: 420)
    let base = bitmap(width: Int(size.width * scale), height: Int(size.height * scale)) { ctx in
        ctx.scaleBy(x: scale, y: scale)
        ctx.setFillColor(rgb(0xFBFBF9))
        ctx.fill(CGRect(x: 0, y: 0, width: 380, height: 420))
        ctx.setFillColor(rgb(0x191917))
        ctx.fill(CGRect(x: 380, y: 0, width: 380, height: 420))
        // Fake interface furniture, so contrast is judged against something realistic.
        for (i, hex) in [0xE5484D, 0x1F6FE5, 0xF1F0ED, 0x30A46C].enumerated() {
            ctx.setFillColor(rgb(UInt(hex)))
            ctx.fill(CGRect(x: 30 + CGFloat(i) * 180, y: 20, width: 150, height: 44))
        }
        for row in 0 ..< 6 {
            ctx.setFillColor(rgb(0x736F67, 0.5))
            ctx.fill(CGRect(x: 40, y: 330 - CGFloat(row) * 16, width: 300 - CGFloat(row % 3) * 60, height: 6))
            ctx.fill(CGRect(x: 420, y: 330 - CGFloat(row) * 16, width: 300 - CGFloat(row % 2) * 80, height: 6))
        }
    }

    var marks: [Annotation] = []
    for (i, color) in InkColor.allCases.enumerated() {
        let x = 40 + CGFloat(i) * 88
        marks.append(Annotation(
            kind: .arrow(from: CGPoint(x: x, y: 130), to: CGPoint(x: x + 60, y: 50)),
            color: color, weight: Weight.allCases[i % 3]
        ))
    }
    marks += [
        Annotation(kind: .arrow(from: CGPoint(x: 60, y: 200), to: CGPoint(x: 330, y: 170)), color: .red, weight: .light),
        Annotation(kind: .arrow(from: CGPoint(x: 60, y: 230), to: CGPoint(x: 330, y: 215)), color: .red, weight: .regular),
        Annotation(kind: .arrow(from: CGPoint(x: 60, y: 262), to: CGPoint(x: 330, y: 262)), color: .red, weight: .heavy),
        Annotation(kind: .arrow(from: CGPoint(x: 350, y: 250), to: CGPoint(x: 364, y: 236)), color: .blue, weight: .regular),
        Annotation(kind: .rectangle(CGRect(x: 420, y: 150, width: 130, height: 70)), color: .yellow),
        Annotation(kind: .rectangle(CGRect(x: 570, y: 150, width: 130, height: 70)), color: .blue, filled: true),
        Annotation(kind: .ellipse(CGRect(x: 420, y: 240, width: 110, height: 60)), color: .green, weight: .heavy),
        Annotation(kind: .line(from: CGPoint(x: 560, y: 250), to: CGPoint(x: 700, y: 290)), color: .white, weight: .light),
        Annotation(kind: .text(origin: CGPoint(x: 40, y: 286), string: "This button is misaligned"), color: .red, filled: true),
        Annotation(kind: .text(origin: CGPoint(x: 40, y: 330), string: "Plain text, light"), color: .blue, weight: .light),
        Annotation(kind: .text(origin: CGPoint(x: 420, y: 316), string: "Label on dark"), color: .yellow, weight: .heavy, filled: true),
        Annotation(kind: .text(origin: CGPoint(x: 600, y: 372), string: "Plain on dark"), color: .white),
        Annotation(kind: .counter(center: CGPoint(x: 60, y: 392), number: 1), color: .red),
        Annotation(kind: .counter(center: CGPoint(x: 100, y: 392), number: 2), color: .blue, weight: .heavy),
        Annotation(kind: .counter(center: CGPoint(x: 142, y: 392), number: 12), color: .yellow, weight: .light),
        Annotation(kind: .highlight(CGRect(x: 36, y: 344, width: 200, height: 22)), color: .yellow),
        Annotation(kind: .highlight(CGRect(x: 416, y: 344, width: 160, height: 22)), color: .yellow),
        Annotation(kind: .redact(CGRect(x: 200, y: 16, width: 180, height: 52))),
        Annotation(kind: .pen((0 ... 40).map { i in
            CGPoint(x: 180 + CGFloat(i) * 4, y: 392 + sin(CGFloat(i) / 3) * 10)
        }), color: .violet),
    ]

    let renderer = AnnotationRenderer()
    guard let out = renderer.flatten(base: base, scale: scale, annotations: marks, outputScale: scale) else {
        fatalError("flatten failed")
    }
    write(out, scale: scale, to: path)
}

func icon(to path: String) {
    let side = 1024
    let base = bitmap(width: side, height: side) { ctx in
        // macOS icon grid: an 824pt rounded square centred on a 1024pt canvas.
        let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
        let shape = CGPath(roundedRect: tile, cornerWidth: 186, cornerHeight: 186, transform: nil)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: rgb(0x000000, 0.25))
        ctx.addPath(shape)
        ctx.setFillColor(rgb(0xFBFBF9))
        ctx.fillPath()
        ctx.restoreGState()

        ctx.addPath(shape)
        ctx.clip()
        let gradient = CGGradient(
            colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
            colors: [rgb(0xFFFFFF), rgb(0xEFEDE7)] as CFArray, locations: [0, 1]
        )!
        ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 924), end: CGPoint(x: 0, y: 100), options: [])

        // Capture corner marks.
        ctx.setStrokeColor(rgb(0x2B2A26))
        ctx.setLineWidth(46)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        let frame = tile.insetBy(dx: 190, dy: 190)
        let arm: CGFloat = 120
        for (corner, dx, dy) in [
            (CGPoint(x: frame.minX, y: frame.minY), 1.0, 1.0), (CGPoint(x: frame.maxX, y: frame.minY), -1.0, 1.0),
            (CGPoint(x: frame.minX, y: frame.maxY), 1.0, -1.0),
        ] {
            ctx.move(to: CGPoint(x: corner.x + arm * dx, y: corner.y))
            ctx.addLine(to: corner)
            ctx.addLine(to: CGPoint(x: corner.x, y: corner.y + arm * dy))
            ctx.strokePath()
        }
    }

    // The arrow comes from the real renderer, scaled up, so the icon matches the product. Its tip
    // sits where the fourth corner mark would be, and it runs back along the diagonal toward the
    // centre, so the mark is symmetrical about that diagonal.
    let unit: CGFloat = 10
    let length = 32.0
    let tip = CGPoint(x: 73.4, y: 29.0)
    let tail = CGPoint(x: tip.x - length / 2.squareRoot(), y: tip.y + length / 2.squareRoot())
    let arrow = Annotation(kind: .arrow(from: tail, to: tip), color: .blue, weight: .heavy)
    guard let out = AnnotationRenderer().flatten(base: base, scale: unit, annotations: [arrow], outputScale: unit) else {
        fatalError("flatten failed")
    }
    write(out, scale: 1, to: path)
}

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    print("usage: shotput-dev preview|icon|editor|overlay <output.png>")
    exit(2)
}
switch arguments[1] {
case "preview": preview(to: arguments[2])
case "icon": icon(to: arguments[2])
case "editor": MainActor.assumeIsolated { editorHarness(to: arguments[2]) }
case "overlay": MainActor.assumeIsolated { overlayHarness(to: arguments[2]) }
case "settings": MainActor.assumeIsolated { settingsHarness(to: arguments[2]) }
case "installer": installerBackground(to: arguments[2])
case "film-capture": MainActor.assumeIsolated { filmCapture(dir: arguments[2]) }
case "film-onboard": MainActor.assumeIsolated { filmOnboard(dir: arguments[2]) }
default:
    print("unknown command \(arguments[1])")
    exit(2)
}
