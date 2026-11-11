import AppKit

public enum Tool: Int, CaseIterable {
    case arrow, line, rectangle, ellipse, text, counter, pen, highlight, redact, crop

    var title: String {
        switch self {
        case .arrow: "Arrow"
        case .line: "Line"
        case .rectangle: "Rectangle"
        case .ellipse: "Ellipse"
        case .text: "Text"
        case .counter: "Step number"
        case .pen: "Pen"
        case .highlight: "Highlighter"
        case .redact: "Redact"
        case .crop: "Crop"
        }
    }

    /// Single-key shortcut while the editor has focus.
    var key: Character {
        switch self {
        case .arrow: "a"
        case .line: "l"
        case .rectangle: "r"
        case .ellipse: "o"
        case .text: "t"
        case .counter: "n"
        case .pen: "p"
        case .highlight: "h"
        case .redact: "b"
        case .crop: "c"
        }
    }

    var supportsFill: Bool { [.rectangle, .ellipse, .text, .redact].contains(self) }
    var supportsWeight: Bool { ![.highlight, .redact, .crop].contains(self) }
    var supportsColor: Bool { self != .crop }
}

public enum Weight: Int, CaseIterable {
    case light, regular, heavy

    var stroke: CGFloat { [2.5, 4, 6.5][rawValue] }
    var fontSize: CGFloat { [14, 19, 28][rawValue] }
    var counterRadius: CGFloat { [11, 14, 19][rawValue] }
    var name: String { ["Thin", "Regular", "Bold"][rawValue] }
}

/// One mark on the screenshot. Coordinates are image points with a top-left origin.
public struct Annotation: Identifiable, Equatable {
    public enum Kind: Equatable {
        case arrow(from: CGPoint, to: CGPoint)
        case line(from: CGPoint, to: CGPoint)
        case rectangle(CGRect)
        case ellipse(CGRect)
        case text(origin: CGPoint, string: String)
        case counter(center: CGPoint, number: Int)
        case pen([CGPoint])
        case highlight(CGRect)
        case redact(CGRect)
    }

    public let id: UUID
    public var kind: Kind
    public var color: InkColor
    public var weight: Weight
    /// Shapes: tinted interior. Text: label pill. Redact: solid block instead of pixels.
    public var filled: Bool

    public init(id: UUID = UUID(), kind: Kind, color: InkColor = .red, weight: Weight = .regular, filled: Bool = false) {
        self.id = id
        self.kind = kind
        self.color = color
        self.weight = weight
        self.filled = filled
    }
}

enum TextMetrics {
    static func font(_ weight: Weight) -> NSFont { .systemFont(ofSize: weight.fontSize, weight: .semibold) }

    static func padding(_ weight: Weight) -> CGSize {
        CGSize(width: (weight.fontSize * 0.5).rounded(), height: (weight.fontSize * 0.22).rounded())
    }

    static func textSize(_ string: String, _ weight: Weight) -> CGSize {
        let measured = (string.isEmpty ? " " : string) as NSString
        let rect = measured.boundingRect(
            with: CGSize(width: 10_000, height: 10_000),
            options: [.usesLineFragmentOrigin],
            attributes: [.font: font(weight)]
        )
        return CGSize(width: ceil(rect.width), height: ceil(rect.height))
    }

    /// The label's outer frame, padding included.
    static func frame(origin: CGPoint, string: String, weight: Weight) -> CGRect {
        let text = textSize(string, weight)
        let pad = padding(weight)
        return CGRect(x: origin.x, y: origin.y, width: text.width + pad.width * 2, height: text.height + pad.height * 2)
    }
}

extension Annotation {
    var tool: Tool {
        switch kind {
        case .arrow: .arrow
        case .line: .line
        case .rectangle: .rectangle
        case .ellipse: .ellipse
        case .text: .text
        case .counter: .counter
        case .pen: .pen
        case .highlight: .highlight
        case .redact: .redact
        }
    }

    /// Geometric bounds, ignoring stroke width.
    var frame: CGRect {
        switch kind {
        case let .arrow(a, b), let .line(a, b):
            return CGRect(from: a, to: b)
        case let .rectangle(r), let .ellipse(r), let .highlight(r), let .redact(r):
            return r
        case let .text(origin, string):
            return TextMetrics.frame(origin: origin, string: string, weight: weight)
        case let .counter(center, _):
            let r = weight.counterRadius
            return CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)
        case let .pen(points):
            guard let first = points.first else { return .zero }
            return points.dropFirst().reduce(CGRect(origin: first, size: .zero)) {
                $0.union(CGRect(origin: $1, size: .zero))
            }
        }
    }

    /// Rect-shaped kinds resize from their corners.
    var resizableRect: CGRect? {
        switch kind {
        case let .rectangle(r), let .ellipse(r), let .highlight(r), let .redact(r): r
        default: nil
        }
    }

    var endpoints: (from: CGPoint, to: CGPoint)? {
        switch kind {
        case let .arrow(a, b), let .line(a, b): (a, b)
        default: nil
        }
    }

    func withRect(_ rect: CGRect) -> Annotation {
        var copy = self
        switch kind {
        case .rectangle: copy.kind = .rectangle(rect)
        case .ellipse: copy.kind = .ellipse(rect)
        case .highlight: copy.kind = .highlight(rect)
        case .redact: copy.kind = .redact(rect)
        default: break
        }
        return copy
    }

    func withEndpoints(from: CGPoint, to: CGPoint) -> Annotation {
        var copy = self
        switch kind {
        case .arrow: copy.kind = .arrow(from: from, to: to)
        case .line: copy.kind = .line(from: from, to: to)
        default: break
        }
        return copy
    }

    func translated(by d: CGPoint) -> Annotation {
        var copy = self
        switch kind {
        case let .arrow(a, b): copy.kind = .arrow(from: a + d, to: b + d)
        case let .line(a, b): copy.kind = .line(from: a + d, to: b + d)
        case let .rectangle(r): copy.kind = .rectangle(r.offsetBy(dx: d.x, dy: d.y))
        case let .ellipse(r): copy.kind = .ellipse(r.offsetBy(dx: d.x, dy: d.y))
        case let .highlight(r): copy.kind = .highlight(r.offsetBy(dx: d.x, dy: d.y))
        case let .redact(r): copy.kind = .redact(r.offsetBy(dx: d.x, dy: d.y))
        case let .text(origin, string): copy.kind = .text(origin: origin + d, string: string)
        case let .counter(center, number): copy.kind = .counter(center: center + d, number: number)
        case let .pen(points): copy.kind = .pen(points.map { $0 + d })
        }
        return copy
    }

    /// Marks whose whole interior is solid: highlights, redactions, and filled shapes.
    var coversArea: Bool {
        switch kind {
        case .highlight, .redact: true
        case .rectangle, .ellipse: filled
        default: false
        }
    }

    /// Whether the point is on the mark's edge, as opposed to anywhere inside it.
    func hitsOutline(_ p: CGPoint, tolerance: CGFloat) -> Bool {
        var outline = self
        outline.filled = false
        if case let .highlight(rect) = kind { outline.kind = .rectangle(rect) }
        if case let .redact(rect) = kind { outline.kind = .rectangle(rect) }
        return outline.hitTest(p, tolerance: tolerance)
    }

    func hitTest(_ p: CGPoint, tolerance: CGFloat) -> Bool {
        let reach = max(weight.stroke / 2, tolerance)
        switch kind {
        case let .arrow(a, b):
            // The head is wider than the shaft, so give arrows a little more reach.
            return p.distance(toSegment: a, b) <= reach + weight.stroke
        case let .line(a, b):
            return p.distance(toSegment: a, b) <= reach
        case let .rectangle(r):
            guard r.insetBy(dx: -reach, dy: -reach).contains(p) else { return false }
            return filled || !r.insetBy(dx: reach, dy: reach).contains(p)
        case let .ellipse(r):
            guard r.width > 0, r.height > 0 else { return false }
            let nx = (p.x - r.midX) / (r.width / 2)
            let ny = (p.y - r.midY) / (r.height / 2)
            let radial = hypot(nx, ny)
            let band = reach / (min(r.width, r.height) / 2)
            return filled ? radial <= 1 + band : abs(radial - 1) <= band
        case .text, .counter, .highlight, .redact:
            return frame.insetBy(dx: -2, dy: -2).contains(p)
        case let .pen(points):
            guard points.count > 1 else { return points.first.map { $0.distance(to: p) <= reach } ?? false }
            return zip(points, points.dropFirst()).contains { p.distance(toSegment: $0, $1) <= reach }
        }
    }
}
