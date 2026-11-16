// Draws a rectangle and an ellipse in every shape fill, with the real renderer, on a busy
// background so the fills can be judged against content.
import AppKit
@testable import ShotputKit

func fillsHarness(to path: String) {
    let fills = ShapeFill.allCases
    let cell = CGSize(width: 150, height: 110)
    let size = CGSize(width: cell.width * CGFloat(fills.count), height: cell.height * 2)
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    guard let ctx = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0,
                              space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { fatalError() }
    ctx.setFillColor(CGColor(gray: 0.97, alpha: 1))
    ctx.fill(CGRect(origin: .zero, size: size))
    ctx.setFillColor(CGColor(gray: 0.55, alpha: 1))
    for y in stride(from: 8.0, to: size.height, by: 14) { ctx.fill(CGRect(x: 10, y: y, width: size.width - 20, height: 5)) }
    guard let base = ctx.makeImage() else { fatalError() }

    var marks: [Annotation] = []
    for (i, fill) in fills.enumerated() {
        for (row, ellipse) in [false, true].enumerated() {
            var style = MarkStyle()
            style.fill = fill
            style.color = i % 2 == 0 ? .red : .blue
            let rect = CGRect(x: CGFloat(i) * cell.width + 18, y: CGFloat(row) * cell.height + 16, width: cell.width - 36, height: cell.height - 32)
            marks.append(Annotation(kind: ellipse ? .ellipse(rect) : .rectangle(rect), style: style))
        }
    }
    guard let out = AnnotationRenderer().flatten(base: base, scale: 1, annotations: marks, outputScale: 2) else { fatalError("flatten failed") }
    write(out, scale: 2, to: path)
    print("wrote \(path)")
}

/// One screenshot on a range of backgrounds: gradients, a colour, transparency, corner radii,
/// shadow depths, and a fixed ratio with the screenshot moved to a corner.
func backdropsHarness(to path: String) {
    guard let source = NSImage(contentsOfFile: "docs/editor.png")?.cgImage(forProposedRect: nil, context: nil, hints: nil) else { fatalError("needs docs/editor.png") }
    // A quarter-size area capture: opaque, square corners.
    let shot = downscaled(source, by: 4)
    let scale: CGFloat = 1
    let gradients = Backdrop.Gradient.presets
    let styles: [Backdrop.Style] = [
        .init(fill: .gradient(gradients[0]), padding: 40, cornerRadius: 10),
        .init(fill: .gradient(gradients[5]), padding: 40, cornerRadius: 24, shadow: 1),
        .init(fill: .gradient(gradients[9]), padding: 24, cornerRadius: 0, shadow: 0.3),
        .init(fill: .gradient(gradients[16]), padding: 40, cornerRadius: 16),
        .init(fill: .color(NSColor(hex: 0xF2F2F7)), padding: 40, cornerRadius: 12, shadow: 0.5),
        .init(fill: .clear, padding: 30, cornerRadius: 18),
        .init(fill: .gradient(gradients[11]), padding: 24, cornerRadius: 12, ratio: .square, alignment: .bottomRight),
        .init(fill: .gradient(gradients[3]), padding: 24, cornerRadius: 12, ratio: .sixteenNine),
    ]
    let tiles = styles.map { Backdrop.compose(shot, scale: scale, style: $0, wallpaper: nil) }
    let cell = CGSize(width: 420, height: 360)
    let columns = 4
    let rows = (tiles.count + columns - 1) / columns
    let size = CGSize(width: cell.width * CGFloat(columns), height: cell.height * CGFloat(rows))
    guard let ctx = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { fatalError() }
    // Checks behind, so transparency shows as transparency.
    for y in stride(from: 0, to: Int(size.height), by: 12) {
        for x in stride(from: 0, to: Int(size.width), by: 12) {
            ctx.setFillColor(CGColor(gray: (x / 12 + y / 12) % 2 == 0 ? 0.92 : 0.84, alpha: 1))
            ctx.fill(CGRect(x: x, y: y, width: 12, height: 12))
        }
    }
    ctx.interpolationQuality = .high
    for (index, tile) in tiles.enumerated() {
        let column = index % columns, row = rows - 1 - index / columns
        let box = CGRect(x: CGFloat(column) * cell.width + 10, y: CGFloat(row) * cell.height + 10, width: cell.width - 20, height: cell.height - 20)
        let fit = min(box.width / CGFloat(tile.width), box.height / CGFloat(tile.height))
        let w = CGFloat(tile.width) * fit, h = CGFloat(tile.height) * fit
        ctx.draw(tile, in: CGRect(x: box.midX - w / 2, y: box.midY - h / 2, width: w, height: h))
    }
    guard let out = ctx.makeImage() else { fatalError() }
    write(out, scale: 1, to: path)
    print("wrote \(path)")
}

private func downscaled(_ image: CGImage, by factor: Int) -> CGImage {
    let w = image.width / factor, h = image.height / factor
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    return ctx.makeImage()!
}
