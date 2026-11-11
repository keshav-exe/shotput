import AppKit

/// Draws annotations into a top-left-origin context measured in image points.
/// The editor canvas and the exporter share this, so what you see is what you copy.
public final class AnnotationRenderer {
    private var mosaicCache: [UUID: (rect: CGRect, base: ObjectIdentifier, image: CGImage)] = [:]

    public init() {}

    /// - Parameters:
    ///   - scale: Base image pixels per point.
    ///   - zoom: Device pixels per point for this context beyond its base transform. Shadows ignore
    ///     the CTM, so they need this to stay proportional.
    public func draw(_ annotations: [Annotation], base: CGImage, scale: CGFloat, zoom: CGFloat, in ctx: CGContext) {
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
        for annotation in annotations {
            draw(annotation, base: base, scale: scale, zoom: zoom, in: ctx)
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    // MARK: Per-kind drawing

    private func draw(_ a: Annotation, base: CGImage, scale: CGFloat, zoom: CGFloat, in ctx: CGContext) {
        ctx.saveGState()
        defer { ctx.restoreGState() }
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)

        switch a.kind {
        case let .arrow(from, to):
            if let bend = a.bend {
                drawCurvedArrow(from: from, control: bend, to: to, a, zoom, ctx)
            } else {
                drawArrow(from: from, to: to, a, zoom, ctx)
            }
        case let .line(from, to):
            let path = CGMutablePath()
            path.move(to: from)
            if let bend = a.bend {
                path.addQuadCurve(to: to, control: bend)
            } else {
                path.addLine(to: to)
            }
            stroke(path, a, zoom, ctx)
        case let .rectangle(rect):
            let radius = min(a.weight.stroke + 2, min(rect.width, rect.height) / 2)
            stroke(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil), a, zoom, ctx)
        case let .ellipse(rect):
            stroke(CGPath(ellipseIn: rect, transform: nil), a, zoom, ctx)
        case let .pen(points):
            stroke(Self.smoothPath(through: points), a, zoom, ctx)
        case let .highlight(rect):
            let radius = min(3, min(rect.width, rect.height) / 2)
            ctx.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
            ctx.setFillColor(a.color.nsColor.withAlphaComponent(0.38).cgColor)
            ctx.fillPath()
        case let .redact(rect):
            drawRedaction(rect, a, base: base, scale: scale, ctx)
        case let .counter(center, number):
            drawCounter(center: center, number: number, a, zoom, ctx)
        case let .text(origin, string):
            drawText(origin: origin, string: string, a, zoom, ctx)
        }
    }

    private static let haloWidth: CGFloat = 1.25

    private func shadowed(_ zoom: CGFloat, _ ctx: CGContext, _ body: () -> Void) {
        ctx.saveGState()
        ctx.setShadow(
            offset: CGSize(width: 0, height: -1.5 * zoom),
            blur: 4 * zoom,
            color: NSColor.black.withAlphaComponent(0.28).cgColor
        )
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        body()
        ctx.endTransparencyLayer()
        ctx.restoreGState()
    }

    private func stroke(_ path: CGPath, _ a: Annotation, _ zoom: CGFloat, _ ctx: CGContext) {
        let width = a.weight.stroke
        shadowed(zoom, ctx) {
            ctx.addPath(path)
            ctx.setStrokeColor(a.color.halo)
            ctx.setLineWidth(width + Self.haloWidth * 2)
            ctx.strokePath()

            if a.filled, a.tool.supportsFill {
                ctx.addPath(path)
                ctx.setFillColor(a.color.nsColor.withAlphaComponent(0.2).cgColor)
                ctx.fillPath()
            }

            ctx.addPath(path)
            ctx.setStrokeColor(a.color.cgColor)
            ctx.setLineWidth(width)
            ctx.strokePath()
        }
    }

    /// A tapered shaft that swells into a swept, round-cornered head.
    private func drawArrow(from start: CGPoint, to end: CGPoint, _ a: Annotation, _ zoom: CGFloat, _ ctx: CGContext) {
        let w = a.weight.stroke
        let delta = end - start
        let length = max(delta.length, 0.001)
        let u = delta * (1 / length)
        let n = CGPoint(x: -u.y, y: u.x)

        // The outline is stroked with a round join to soften every corner, so the geometry
        // sits inside the final silhouette by half that stroke.
        let rounding = w * 0.5
        let headLength = min(max(w * 4.4, 13), length * 0.62)
        let headHalf = headLength * 0.52
        let tip = end - u * (rounding / 2)
        let wings = tip - u * headLength
        let neck = tip - u * (headLength * 0.8)
        let neckHalf = min(w * 0.38, headHalf * 0.4)
        let tailHalf = w * 0.14

        let path = CGMutablePath()
        path.move(to: start + n * tailHalf)
        path.addLine(to: neck + n * neckHalf)
        path.addLine(to: wings + n * headHalf)
        path.addLine(to: tip)
        path.addLine(to: wings - n * headHalf)
        path.addLine(to: neck - n * neckHalf)
        path.addLine(to: start - n * tailHalf)
        path.closeSubpath()

        shadowed(zoom, ctx) {
            ctx.addPath(path)
            ctx.setFillColor(a.color.halo)
            ctx.setStrokeColor(a.color.halo)
            ctx.setLineWidth(rounding + Self.haloWidth * 2)
            ctx.drawPath(using: .fillStroke)

            ctx.addPath(path)
            ctx.setFillColor(a.color.cgColor)
            ctx.setStrokeColor(a.color.cgColor)
            ctx.setLineWidth(rounding)
            ctx.drawPath(using: .fillStroke)
        }
    }

    /// The same tapered arrow, with its shaft following a quadratic curve. The head points
    /// along the curve's direction where it arrives.
    private func drawCurvedArrow(from start: CGPoint, control: CGPoint, to end: CGPoint, _ a: Annotation, _ zoom: CGFloat, _ ctx: CGContext) {
        let w = a.weight.stroke
        let arrival = end - control
        let arrivalLength = max(arrival.length, 0.001)
        let u = arrival * (1 / arrivalLength)
        let n = CGPoint(x: -u.y, y: u.x)

        let samples = 48
        let curve = (0 ... samples).map { quadPoint(start, control, end, CGFloat($0) / CGFloat(samples)) }
        let length = zip(curve, curve.dropFirst()).reduce(0) { $0 + $1.0.distance(to: $1.1) }
        let rounding = w * 0.5
        let headLength = min(max(w * 4.4, 13), length * 0.62)
        let headHalf = headLength * 0.52
        let tip = end - u * (rounding / 2)
        let wings = tip - u * headLength
        let neck = tip - u * (headLength * 0.8)
        let neckHalf = min(w * 0.38, headHalf * 0.4)
        let tailHalf = w * 0.14

        // The shaft runs along the curve until it reaches the neck of the head.
        var shaft: [CGPoint] = []
        for point in curve {
            if point.distance(to: tip) <= headLength * 0.8 { break }
            shaft.append(point)
        }
        guard shaft.count >= 2 else {
            drawArrow(from: start, to: end, a, zoom, ctx)
            return
        }
        shaft.append(neck)

        var left: [CGPoint] = []
        var right: [CGPoint] = []
        for (index, point) in shaft.enumerated() {
            let previous = shaft[max(index - 1, 0)]
            let next = shaft[min(index + 1, shaft.count - 1)]
            let direction = next - previous
            let normal = CGPoint(x: -direction.y, y: direction.x) * (1 / max(direction.length, 0.001))
            let t = CGFloat(index) / CGFloat(shaft.count - 1)
            let half = tailHalf + (neckHalf - tailHalf) * t
            left.append(point + normal * half)
            right.append(point - normal * half)
        }

        let path = CGMutablePath()
        path.move(to: left[0])
        left.dropFirst().forEach { path.addLine(to: $0) }
        path.addLine(to: wings + n * headHalf)
        path.addLine(to: tip)
        path.addLine(to: wings - n * headHalf)
        right.reversed().forEach { path.addLine(to: $0) }
        path.closeSubpath()

        shadowed(zoom, ctx) {
            ctx.addPath(path)
            ctx.setFillColor(a.color.halo)
            ctx.setStrokeColor(a.color.halo)
            ctx.setLineWidth(rounding + Self.haloWidth * 2)
            ctx.drawPath(using: .fillStroke)

            ctx.addPath(path)
            ctx.setFillColor(a.color.cgColor)
            ctx.setStrokeColor(a.color.cgColor)
            ctx.setLineWidth(rounding)
            ctx.drawPath(using: .fillStroke)
        }
    }

    private func drawCounter(center: CGPoint, number: Int, _ a: Annotation, _ zoom: CGFloat, _ ctx: CGContext) {
        let radius = a.weight.counterRadius
        let circle = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        shadowed(zoom, ctx) {
            ctx.setFillColor(a.color.halo)
            ctx.fillEllipse(in: circle.insetBy(dx: -Self.haloWidth - 0.5, dy: -Self.haloWidth - 0.5))
            ctx.setFillColor(a.color.cgColor)
            ctx.fillEllipse(in: circle)
        }
        let label = NSAttributedString(string: "\(number)", attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: radius * (number > 9 ? 0.95 : 1.15), weight: .bold),
            .foregroundColor: a.color.onInk,
        ])
        let size = label.size()
        label.draw(at: CGPoint(x: center.x - size.width / 2, y: center.y - size.height / 2))
    }

    private func drawText(origin: CGPoint, string: String, _ a: Annotation, _ zoom: CGFloat, _ ctx: CGContext) {
        let frame = TextMetrics.frame(origin: origin, string: string, weight: a.weight)
        let pad = TextMetrics.padding(a.weight)
        let textRect = frame.insetBy(dx: pad.width, dy: pad.height)
        let font = TextMetrics.font(a.weight)
        let options: NSString.DrawingOptions = [.usesLineFragmentOrigin]

        if a.filled {
            let radius = min(frame.height / 2, a.weight.fontSize * 0.45)
            let pill = CGPath(roundedRect: frame, cornerWidth: radius, cornerHeight: radius, transform: nil)
            shadowed(zoom, ctx) {
                ctx.addPath(pill)
                ctx.setFillColor(a.color.halo)
                ctx.setStrokeColor(a.color.halo)
                ctx.setLineWidth(Self.haloWidth * 2)
                ctx.drawPath(using: .fillStroke)
                ctx.addPath(pill)
                ctx.setFillColor(a.color.cgColor)
                ctx.fillPath()
            }
            (string as NSString).draw(with: textRect, options: options, attributes: [
                .font: font, .foregroundColor: a.color.onInk,
            ])
        } else {
            // Outline pass first, then the fill, so the halo sits behind the glyphs.
            let outline = Self.haloWidth * 2 + 1
            shadowed(zoom, ctx) {
                (string as NSString).draw(with: textRect, options: options, attributes: [
                    .font: font,
                    .foregroundColor: NSColor(cgColor: a.color.halo) ?? .white,
                    .strokeColor: NSColor(cgColor: a.color.halo) ?? .white,
                    .strokeWidth: -(outline / a.weight.fontSize * 100),
                ])
                (string as NSString).draw(with: textRect, options: options, attributes: [
                    .font: font, .foregroundColor: a.color.nsColor,
                ])
            }
        }
    }

    private func drawRedaction(_ rect: CGRect, _ a: Annotation, base: CGImage, scale: CGFloat, _ ctx: CGContext) {
        let image = CGRect(x: 0, y: 0, width: CGFloat(base.width) / scale, height: CGFloat(base.height) / scale)
        let area = rect.intersection(image)
        guard area.width >= 1, area.height >= 1 else { return }
        if a.filled {
            let radius = min(2, min(area.width, area.height) / 2)
            ctx.addPath(CGPath(roundedRect: area, cornerWidth: radius, cornerHeight: radius, transform: nil))
            ctx.setFillColor(a.color.cgColor)
            ctx.fillPath()
            return
        }
        guard let mosaic = mosaic(of: area, id: a.id, base: base, scale: scale) else { return }
        ctx.saveGState()
        ctx.interpolationQuality = .none
        Self.drawImage(mosaic, in: area, ctx)
        ctx.restoreGState()
    }

    /// The region averaged down to a handful of cells. Each cell is the mean of what it covers,
    /// so text turns into grey blocks instead of vanishing, and the cells are too coarse to read
    /// back. Drawn scaled up without smoothing, it gives the familiar mosaic.
    private func mosaic(of area: CGRect, id: UUID, base: CGImage, scale: CGFloat) -> CGImage? {
        let baseID = ObjectIdentifier(base)
        if let cached = mosaicCache[id], cached.rect == area, cached.base == baseID { return cached.image }

        let pixels = CGRect(
            x: area.minX * scale, y: area.minY * scale, width: area.width * scale, height: area.height * scale
        ).integral
        let cell = max(10, min(area.width, area.height) / 5) * scale
        let columns = max(1, Int((pixels.width / cell).rounded(.up)))
        let rows = max(1, Int((pixels.height / cell).rounded(.up)))
        guard let region = base.cropping(to: pixels), let small = CGContext(
            data: nil, width: columns, height: rows, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        small.interpolationQuality = .high
        small.draw(region, in: CGRect(x: 0, y: 0, width: columns, height: rows))
        guard let image = small.makeImage() else { return nil }
        mosaicCache[id] = (area, baseID, image)
        return image
    }

    // MARK: Helpers

    /// Draws an upright image into a flipped context.
    static func drawImage(_ image: CGImage, in rect: CGRect, _ ctx: CGContext) {
        ctx.saveGState()
        ctx.translateBy(x: rect.minX, y: rect.maxY)
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(image, in: CGRect(origin: .zero, size: rect.size))
        ctx.restoreGState()
    }

    /// Quadratic midpoint smoothing, which removes the jitter of raw mouse samples.
    static func smoothPath(through points: [CGPoint]) -> CGPath {
        let path = CGMutablePath()
        guard let first = points.first else { return path }
        path.move(to: first)
        guard points.count > 2 else {
            path.addLine(to: points.last ?? first)
            return path
        }
        for i in 1 ..< points.count - 1 {
            let mid = (points[i] + points[i + 1]) * 0.5
            path.addQuadCurve(to: mid, control: points[i])
        }
        path.addLine(to: points[points.count - 1])
        return path
    }

    // MARK: Export

    /// Flattens the base image and its annotations.
    /// - Parameter outputScale: Pixels per point in the result. Pass `scale` for full resolution.
    public func flatten(base: CGImage, scale: CGFloat, annotations: [Annotation], outputScale: CGFloat) -> CGImage? {
        if annotations.isEmpty, outputScale == scale { return base }
        let width = Int((CGFloat(base.width) / scale * outputScale).rounded())
        let height = Int((CGFloat(base.height) / scale * outputScale).rounded())
        let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
        let space = base.colorSpace.flatMap { $0.model == .rgb && $0.supportsOutput ? $0 : nil } ?? sRGB
        guard width > 0, height > 0, let ctx = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        ctx.interpolationQuality = .high
        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: outputScale, y: -outputScale)
        let bounds = CGRect(x: 0, y: 0, width: CGFloat(base.width) / scale, height: CGFloat(base.height) / scale)
        Self.drawImage(base, in: bounds, ctx)
        draw(annotations, base: base, scale: scale, zoom: outputScale, in: ctx)
        return ctx.makeImage()
    }
}
