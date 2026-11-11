import CoreGraphics

/// Turns a freehand stroke into the shape it was meant to be, the way Markup does: a straight
/// stroke becomes a line, a stroke with a hook at its far end an arrow, and a closed loop an
/// ellipse or a rectangle. Anything ambiguous stays a sketch.
enum ShapeRecognizer {
    enum Shape: Equatable {
        case line(from: CGPoint, to: CGPoint)
        case arrow(from: CGPoint, to: CGPoint)
        case rectangle(CGRect)
        case ellipse(CGRect)

        var name: String {
            switch self {
            case .line: "line"
            case .arrow: "arrow"
            case let .rectangle(rect): abs(rect.width - rect.height) < 0.5 ? "square" : "rectangle"
            case let .ellipse(rect): abs(rect.width - rect.height) < 0.5 ? "circle" : "ellipse"
            }
        }

        var kind: Annotation.Kind {
            switch self {
            case let .line(a, b): .line(from: a, to: b)
            case let .arrow(a, b): .arrow(from: a, to: b)
            case let .rectangle(rect): .rectangle(rect)
            case let .ellipse(rect): .ellipse(rect)
            }
        }
    }

    static func recognize(_ raw: [CGPoint]) -> Shape? {
        let points = resample(raw, count: 64)
        guard points.count >= 8, let first = points.first, let last = points.last else { return nil }
        let bounds = points.dropFirst().reduce(CGRect(origin: first, size: .zero)) { $0.union(CGRect(origin: $1, size: .zero)) }
        let size = max(bounds.width, bounds.height)
        guard size >= 16 else { return nil }
        let length = pathLength(points)

        // Closed: the end comes back near the start, and the stroke goes most of the way round.
        if first.distance(to: last) < size * 0.22, length > (bounds.width + bounds.height) * 1.5 {
            return closedShape(points, bounds)
        }

        // Straight: barely strays from the line between its ends.
        let chord = first.distance(to: last)
        if chord > 16, maxDeviation(points, first, last) < chord * 0.07, length < chord * 1.12 {
            return .line(from: first, to: last)
        }

        return arrow(points)
    }

    /// A straight shaft to the point farthest from the start, then a short hook back from it.
    private static func arrow(_ points: [CGPoint]) -> Shape? {
        guard let start = points.first else { return nil }
        guard let tipIndex = points.indices.max(by: { points[$0].distance(to: start) < points[$1].distance(to: start) }) else {
            return nil
        }
        let fraction = Double(tipIndex) / Double(points.count - 1)
        guard fraction > 0.45, fraction < 0.93 else { return nil }
        let tip = points[tipIndex]
        let shaftLength = start.distance(to: tip)
        guard shaftLength > 24 else { return nil }
        let shaft = Array(points[...tipIndex])
        guard maxDeviation(shaft, start, tip) < shaftLength * 0.08 else { return nil }
        let hook = Array(points[tipIndex...])
        let hookLength = pathLength(hook)
        guard hookLength > shaftLength * 0.08, hookLength < shaftLength * 0.9,
              hook.allSatisfy({ $0.distance(to: tip) < shaftLength * 0.45 }) else { return nil }
        return .arrow(from: start, to: tip)
    }

    private static func closedShape(_ points: [CGPoint], _ bounds: CGRect) -> Shape? {
        guard bounds.width > 12, bounds.height > 12 else { return nil }
        let halfW = bounds.width / 2, halfH = bounds.height / 2
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let ellipseError = points.reduce(0) { sum, p in
            sum + abs(hypot((p.x - center.x) / halfW, (p.y - center.y) / halfH) - 1)
        } / CGFloat(points.count)
        let rectangleError = points.reduce(0) { sum, p in
            let toEdge = min(abs(p.x - bounds.minX), abs(p.x - bounds.maxX), abs(p.y - bounds.minY), abs(p.y - bounds.maxY))
            return sum + toEdge / min(halfW, halfH)
        } / CGFloat(points.count)

        // Near-equal sides were almost certainly meant to be equal.
        var rect = bounds
        if abs(bounds.width - bounds.height) < max(bounds.width, bounds.height) * 0.1 {
            let side = (bounds.width + bounds.height) / 2
            rect = CGRect(x: center.x - side / 2, y: center.y - side / 2, width: side, height: side)
        }
        if rectangleError < ellipseError, rectangleError < 0.13 { return .rectangle(rect) }
        if ellipseError <= rectangleError, ellipseError < 0.14 { return .ellipse(rect) }
        return nil
    }

    // MARK: Geometry

    private static func pathLength(_ points: [CGPoint]) -> CGFloat {
        zip(points, points.dropFirst()).reduce(0) { $0 + $1.0.distance(to: $1.1) }
    }

    private static func maxDeviation(_ points: [CGPoint], _ a: CGPoint, _ b: CGPoint) -> CGFloat {
        points.map { $0.distance(toSegment: a, b) }.max() ?? 0
    }

    /// Evenly spaced points along the stroke, so fast and slow drawing compare alike.
    private static func resample(_ points: [CGPoint], count: Int) -> [CGPoint] {
        guard points.count > 1 else { return points }
        let total = pathLength(points)
        guard total > 0 else { return [points[0]] }
        let step = total / CGFloat(count - 1)
        var result = [points[0]]
        var carried: CGFloat = 0
        for (a, b) in zip(points, points.dropFirst()) {
            var segment = a.distance(to: b)
            var from = a
            while carried + segment >= step {
                let t = (step - carried) / segment
                let point = from + (b - from) * t
                result.append(point)
                segment -= step - carried
                from = point
                carried = 0
            }
            carried += segment
        }
        if result.count < count, let last = points.last { result.append(last) }
        return result
    }
}
