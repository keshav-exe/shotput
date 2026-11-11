// Checks for shape recognition and curved lines, plus a render of curved arrows at every weight.
import AppKit
@testable import ShotputKit

func drawingChecks(_ expect: (Bool, String) -> Void, render path: String) {
    func stroke(_ f: (CGFloat) -> CGPoint, steps: Int = 60) -> [CGPoint] {
        (0 ... steps).map { f(CGFloat($0) / CGFloat(steps)) }
    }
    // Hand wobble, so the checks do not pass only on perfect input.
    func wobble(_ points: [CGPoint]) -> [CGPoint] {
        points.enumerated().map { i, p in CGPoint(x: p.x + sin(CGFloat(i) * 1.7) * 1.5, y: p.y + cos(CGFloat(i) * 2.3) * 1.5) }
    }

    let circle = wobble(stroke { t in CGPoint(x: 100 + cos(t * 2 * .pi) * 50, y: 100 + sin(t * 2 * .pi) * 48) })
    if case .ellipse? = ShapeRecognizer.recognize(circle) { expect(true, "a round loop becomes a circle") } else {
        expect(false, "a round loop becomes a circle, got \(String(describing: ShapeRecognizer.recognize(circle)))")
    }
    let corners = [CGPoint(x: 20, y: 20), CGPoint(x: 220, y: 22), CGPoint(x: 218, y: 120), CGPoint(x: 22, y: 118), CGPoint(x: 21, y: 24)]
    let box = wobble(zip(corners, corners.dropFirst()).flatMap { a, b in stroke({ a + (b - a) * $0 }, steps: 15) })
    if case .rectangle? = ShapeRecognizer.recognize(box) { expect(true, "a boxy loop becomes a rectangle") } else {
        expect(false, "a boxy loop becomes a rectangle, got \(String(describing: ShapeRecognizer.recognize(box)))")
    }
    let straight = wobble(stroke { CGPoint(x: 10 + $0 * 200, y: 50 + $0 * 60) })
    if case .line? = ShapeRecognizer.recognize(straight) { expect(true, "a straight stroke becomes a line") } else {
        expect(false, "a straight stroke becomes a line")
    }
    let shaft = stroke({ CGPoint(x: 10 + $0 * 200, y: 100) }, steps: 40)
    let hook = stroke({ CGPoint(x: 210 - $0 * 30, y: 100 - $0 * 22) }, steps: 10)
    if case let .arrow(_, tip)? = ShapeRecognizer.recognize(wobble(shaft + hook)) {
        expect(tip.distance(to: CGPoint(x: 210, y: 100)) < 6, "a stroke with a hook becomes an arrow pointing at the hook")
    } else {
        expect(false, "a stroke with a hook becomes an arrow")
    }
    let scribble = stroke { t in CGPoint(x: 20 + t * 180, y: 60 + sin(t * 18) * 30) }
    expect(ShapeRecognizer.recognize(scribble) == nil, "a scribble stays a sketch")
    expect(ShapeRecognizer.recognize(stroke { CGPoint(x: $0 * 8, y: $0 * 3) }) == nil, "a tiny stroke stays a sketch")

    // Curves: the handle sits on the curve, drags shape it, and near-straight snaps straight.
    let line = Annotation(kind: .arrow(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 200, y: 0)))
    let bent = line.bent(through: CGPoint(x: 100, y: 60))
    expect(bent.bendHandle.map { $0.distance(to: CGPoint(x: 100, y: 60)) < 0.5 } ?? false, "the curve passes through the dragged handle")
    expect(bent.hitTest(CGPoint(x: 100, y: 60), tolerance: 4), "a curved arrow is hit along its curve")
    expect(!bent.hitTest(CGPoint(x: 100, y: 0), tolerance: 4), "and not along the old straight line")
    expect(line.bent(through: CGPoint(x: 100, y: 2)).bend == nil, "a nearly straight drag snaps straight")
    let moved = bent.withEndpoints(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 300, y: 0))
    expect(moved.bendHandle.map { $0.y > 50 } ?? false, "moving an end keeps the bend")

    // Render curved arrows and lines at each weight.
    let size = CGSize(width: 560, height: 220)
    let base = bitmap(width: Int(size.width * 2), height: Int(size.height * 2)) { ctx in
        ctx.setFillColor(rgb(0xFBFBF9))
        ctx.fill(CGRect(x: 0, y: 0, width: size.width * 2, height: size.height * 2))
    }
    var marks: [Annotation] = []
    for (i, weight) in Weight.allCases.enumerated() {
        let x = 30 + CGFloat(i) * 130
        marks.append(Annotation(kind: .arrow(from: CGPoint(x: x, y: 190), to: CGPoint(x: x + 100, y: 40)), color: .red, weight: weight)
            .bent(through: CGPoint(x: x + 20, y: 90)))
        marks.append(Annotation(kind: .line(from: CGPoint(x: x, y: 205), to: CGPoint(x: x + 100, y: 205)), color: .blue, weight: weight)
            .bent(through: CGPoint(x: x + 50, y: 180)))
    }
    if let out = AnnotationRenderer().flatten(base: base, scale: 2, annotations: marks, outputScale: 2) {
        write(out, scale: 2, to: path)
    }
}
