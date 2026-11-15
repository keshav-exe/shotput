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
