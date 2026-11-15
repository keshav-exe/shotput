import AppKit
import CoreImage

/// Draws annotations into a top-left-origin context measured in image points.
/// The editor canvas and the exporter share this, so what you see is what you copy.
public final class AnnotationRenderer {
    private struct RedactionKey: Equatable {
        let rect: CGRect
        let base: ObjectIdentifier
        let mode: RedactMode
        let size: CGFloat
    }

    private var redactionCache: [UUID: (key: RedactionKey, image: CGImage)] = [:]
    private static let imageContext = CIContext(options: [.cacheIntermediates: false])

    public init() {}

    /// - Parameters:
    ///   - scale: Base image pixels per point.
    ///   - zoom: Device pixels per point for this context beyond its base transform. Shadows ignore
    ///     the CTM, so they need this to stay proportional.
    public func draw(_ annotations: [Annotation], base: CGImage, scale: CGFloat, zoom: CGFloat, in ctx: CGContext) {
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
        let bounds = CGRect(x: 0, y: 0, width: CGFloat(base.width) / scale, height: CGFloat(base.height) / scale)
        // Every spotlight shares one dimmed layer, drawn where the first one sits in the stack, so
        // two spotlights light two areas instead of dimming each other.
        let spotlights = annotations.filter { if case .spotlight = $0.kind { true } else { false } }
        var dimmed = false
        for annotation in annotations {
            if case .spotlight = annotation.kind {
                if !dimmed { drawSpotlights(spotlights, bounds: bounds, ctx) }
                dimmed = true
                continue
            }
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
            switch a.style.arrow {
            case .tapered:
                if let bend = a.bend {
                    drawCurvedArrow(from: from, control: bend, to: to, a, zoom, ctx)
                } else {
                    drawArrow(from: from, to: to, a, zoom, ctx)
                }
            case .uniform, .double:
                drawEvenArrow(a, zoom, ctx)
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
            let radius = min(max(a.style.cornerRadius, 0), min(rect.width, rect.height) / 2)
            shape(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil), a, zoom, ctx)
        case let .ellipse(rect):
            shape(CGPath(ellipseIn: rect, transform: nil), a, zoom, ctx)
        case let .pen(points):
            stroke(Self.smoothPath(through: points), a, zoom, ctx)
        case let .highlight(rect):
            let radius = min(3, min(rect.width, rect.height) / 2)
            layer(a, zoom, ctx) {
                ctx.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
                ctx.setFillColor(a.color.nsColor.withAlphaComponent(0.38).cgColor)
                ctx.fillPath()
            }
        case let .redact(rect):
            drawRedaction(rect, a, base: base, scale: scale, zoom, ctx)
        case let .counter(center, number):
            drawCounter(center: center, number: number, a, zoom, ctx)
        case let .text(origin, string):
            drawText(origin: origin, string: string, a, zoom, ctx)
        case .spotlight:
            break
        }
    }

    private static let haloWidth: CGFloat = 1.25

    /// Draws one mark as a unit: its opacity applies to the whole, and its shadow falls once.
    private func layer(_ a: Annotation, _ zoom: CGFloat, _ ctx: CGContext, _ body: () -> Void) {
        ctx.saveGState()
        ctx.setAlpha(min(max(a.style.opacity, 0.05), 1))
        if a.style.shadow {
            ctx.setShadow(
                offset: CGSize(width: 0, height: -1.5 * zoom),
                blur: 4 * zoom,
                color: NSColor.black.withAlphaComponent(0.28).cgColor
            )
        }
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        body()
        ctx.endTransparencyLayer()
        ctx.restoreGState()
    }

    private func dash(_ a: Annotation, _ width: CGFloat, _ ctx: CGContext) {
        guard a.style.dashed else { return }
        // Round caps grow each dash by the line width, so the gaps are set wider to compensate.
        ctx.setLineDash(phase: 0, lengths: [max(width * 1.6, 2), width * 2.6 + 2])
    }

    private func stroke(_ path: CGPath, _ a: Annotation, _ zoom: CGFloat, _ ctx: CGContext) {
        let width = a.lineWidth
        layer(a, zoom, ctx) {
            dash(a, width, ctx)
            ctx.addPath(path)
            ctx.setStrokeColor(a.color.halo)
            ctx.setLineWidth(width + Self.haloWidth * 2)
            ctx.strokePath()

            ctx.addPath(path)
            ctx.setStrokeColor(a.color.cgColor)
            ctx.setLineWidth(width)
            ctx.strokePath()
        }
    }

    /// Rectangles and ellipses: outline, solid fill, or a tinted fill inside a border.
    private func shape(_ path: CGPath, _ a: Annotation, _ zoom: CGFloat, _ ctx: CGContext) {
        let width = a.lineWidth
        layer(a, zoom, ctx) {
            switch a.style.fill {
            case .solid:
                ctx.addPath(path)
                ctx.setStrokeColor(a.color.halo)
                ctx.setLineWidth(Self.haloWidth * 2)
                ctx.strokePath()
                ctx.addPath(path)
                ctx.setFillColor(a.color.cgColor)
                ctx.fillPath()
            case .outline, .tinted:
                if a.style.fill == .tinted {
                    ctx.addPath(path)
                    ctx.setFillColor(a.color.nsColor.withAlphaComponent(0.22).cgColor)
                    ctx.fillPath()
                }
                dash(a, width, ctx)
                ctx.addPath(path)
                ctx.setStrokeColor(a.color.halo)
                ctx.setLineWidth(width + Self.haloWidth * 2)
                ctx.strokePath()
                ctx.addPath(path)
                ctx.setStrokeColor(a.color.cgColor)
                ctx.setLineWidth(width)
                ctx.strokePath()
            }
        }
    }

    /// A tapered shaft that swells into a swept, round-cornered head.
    private func drawArrow(from start: CGPoint, to end: CGPoint, _ a: Annotation, _ zoom: CGFloat, _ ctx: CGContext) {
        let w = a.lineWidth
        let delta = end - start
        let length = max(delta.length, 0.001)
        let u = delta * (1 / length)
        let n = CGPoint(x: -u.y, y: u.x)

        // The outline is stroked with a round join to soften every corner, so the geometry
        // sits inside the final silhouette by half that stroke.
        let rounding = w * 0.5
        let headLength = min(max(w * 4.4, 13) * a.style.head.factor, length * 0.62)
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
        fillOutline(path, rounding: rounding, a, zoom, ctx)
    }

    /// The same tapered arrow, with its shaft following a quadratic curve. The head points
    /// along the curve's direction where it arrives.
    private func drawCurvedArrow(from start: CGPoint, control: CGPoint, to end: CGPoint, _ a: Annotation, _ zoom: CGFloat, _ ctx: CGContext) {
        let w = a.lineWidth
        let arrival = end - control
        let arrivalLength = max(arrival.length, 0.001)
        let u = arrival * (1 / arrivalLength)
        let n = CGPoint(x: -u.y, y: u.x)

        let samples = 48
        let curve = (0 ... samples).map { quadPoint(start, control, end, CGFloat($0) / CGFloat(samples)) }
        let length = zip(curve, curve.dropFirst()).reduce(0) { $0 + $1.0.distance(to: $1.1) }
        let rounding = w * 0.5
        let headLength = min(max(w * 4.4, 13) * a.style.head.factor, length * 0.62)
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
        fillOutline(path, rounding: rounding, a, zoom, ctx)
    }

    /// A shaft of even width, straight or curved, dashed if asked, with a head at the end, or
    /// at both ends for the double-headed style.
    private func drawEvenArrow(_ a: Annotation, _ zoom: CGFloat, _ ctx: CGContext) {
        guard let ends = a.endpoints, var points = a.pathPoints(samples: 48), points.count >= 2 else { return }
        let w = a.lineWidth
        let length = zip(points, points.dropFirst()).reduce(0) { $0 + $1.0.distance(to: $1.1) }
        let double = a.style.arrow == .double
        let headLength = min(max(w * 3.4, 11) * a.style.head.factor, length * (double ? 0.4 : 0.6))
        let headHalf = headLength * 0.55

        func head(at tip: CGPoint, from control: CGPoint) -> CGPath {
            let d = tip - control
            let u = d * (1 / max(d.length, 0.001))
            let n = CGPoint(x: -u.y, y: u.x)
            let back = tip - u * headLength
            let path = CGMutablePath()
            path.move(to: tip)
            path.addLine(to: back + n * headHalf)
            path.addLine(to: back - n * headHalf)
            path.closeSubpath()
            return path
        }

        // Trim the shaft so its round cap hides under each head instead of poking past the tip.
        let trim = headLength * 0.6
        while points.count > 2, let last = points.last, last.distance(to: ends.to) < trim { points.removeLast() }
        if let last = points.last, points.count >= 2 {
            let previous = points[points.count - 2]
            let d = last - previous
            if last.distance(to: ends.to) < trim {
                points[points.count - 1] = ends.to - d * (1 / max(d.length, 0.001)) * trim
            }
        }
        if double {
            while points.count > 2, points[0].distance(to: ends.from) < trim { points.removeFirst() }
            let d = points[1] - points[0]
            if points[0].distance(to: ends.from) < trim {
                points[0] = ends.from + d * (1 / max(d.length, 0.001)) * trim
            }
        }
        let shaft = CGMutablePath()
        shaft.addLines(between: points)

        var heads = [head(at: ends.to, from: a.bend ?? ends.from)]
        if double { heads.append(head(at: ends.from, from: a.bend ?? ends.to)) }

        layer(a, zoom, ctx) {
            for (color, extra) in [(a.color.halo, Self.haloWidth * 2), (a.color.cgColor, CGFloat(0))] {
                ctx.saveGState()
                dash(a, w, ctx)
                ctx.addPath(shaft)
                ctx.setStrokeColor(color)
                ctx.setLineWidth(w + extra)
                ctx.strokePath()
                ctx.restoreGState()
                for path in heads {
                    ctx.addPath(path)
                    ctx.setFillColor(color)
                    ctx.setStrokeColor(color)
                    ctx.setLineWidth(w * 0.5 + extra)
                    ctx.drawPath(using: .fillStroke)
                }
            }
        }
    }

    private func fillOutline(_ path: CGPath, rounding: CGFloat, _ a: Annotation, _ zoom: CGFloat, _ ctx: CGContext) {
        layer(a, zoom, ctx) {
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
        let radius = max(a.style.size, 8) / 2
        let disc = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        let style = a.style.counter
        func outline(_ rect: CGRect) -> CGPath {
            let corner = rect.width * 0.26
            return style == .square
                ? CGPath(roundedRect: rect, cornerWidth: corner, cornerHeight: corner, transform: nil)
                : CGPath(ellipseIn: rect, transform: nil)
        }
        let ring = max(radius * 0.16, 1.5)
        // A ring is white inside with the ink as its border and number.
        let glyph: NSColor = style == .ring ? a.color.nsColor : a.color.onInk
        let label = NSAttributedString(string: "\(number)", attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: radius * (number > 9 ? 0.95 : 1.15), weight: .bold),
            .foregroundColor: glyph,
        ])
        let size = label.size()
        layer(a, zoom, ctx) {
            ctx.addPath(outline(disc.insetBy(dx: -Self.haloWidth - 0.5, dy: -Self.haloWidth - 0.5)))
            ctx.setFillColor(a.color.halo)
            ctx.fillPath()
            if style == .ring {
                ctx.addPath(outline(disc))
                ctx.setFillColor(.white)
                ctx.fillPath()
                ctx.addPath(outline(disc.insetBy(dx: ring / 2, dy: ring / 2)))
                ctx.setStrokeColor(a.color.cgColor)
                ctx.setLineWidth(ring)
                ctx.strokePath()
            } else {
                ctx.addPath(outline(disc))
                ctx.setFillColor(a.color.cgColor)
                ctx.fillPath()
            }
            label.draw(at: CGPoint(x: center.x - size.width / 2, y: center.y - size.height / 2))
        }
    }

    private func drawText(origin: CGPoint, string: String, _ a: Annotation, _ zoom: CGFloat, _ ctx: CGContext) {
        let frame = TextMetrics.frame(origin: origin, string: string, style: a.style)
        let pad = TextMetrics.padding(a.style)
        let textRect = frame.insetBy(dx: pad.width, dy: pad.height)
        let font = TextMetrics.font(a.style)
        let options: NSString.DrawingOptions = [.usesLineFragmentOrigin]
        let size = max(a.style.size, 4)

        layer(a, zoom, ctx) {
            switch a.style.text {
            case .pill:
                let radius = min(frame.height / 2, size * 0.45)
                let pill = CGPath(roundedRect: frame, cornerWidth: radius, cornerHeight: radius, transform: nil)
                ctx.addPath(pill)
                ctx.setFillColor(a.color.halo)
                ctx.setStrokeColor(a.color.halo)
                ctx.setLineWidth(Self.haloWidth * 2)
                ctx.drawPath(using: .fillStroke)
                ctx.addPath(pill)
                ctx.setFillColor(a.color.cgColor)
                ctx.fillPath()
                (string as NSString).draw(with: textRect, options: options, attributes: [
                    .font: font, .foregroundColor: a.color.onInk,
                ])
            case .outlined:
                // Outline pass first, then the fill, so the halo sits behind the glyphs.
                let outline = max(Self.haloWidth * 2 + 1, size * 0.14)
                let halo = NSColor(cgColor: a.color.halo)?.withAlphaComponent(1) ?? .white
                (string as NSString).draw(with: textRect, options: options, attributes: [
                    .font: font,
                    .foregroundColor: halo,
                    .strokeColor: halo,
                    .strokeWidth: -(outline / size * 100),
                ])
                (string as NSString).draw(with: textRect, options: options, attributes: [
                    .font: font, .foregroundColor: a.color.nsColor,
                ])
            case .plain:
                (string as NSString).draw(with: textRect, options: options, attributes: [
                    .font: font, .foregroundColor: a.color.nsColor,
                ])
            }
        }
    }

    private func drawSpotlights(_ spotlights: [Annotation], bounds: CGRect, _ ctx: CGContext) {
        guard let first = spotlights.first else { return }
        ctx.saveGState()
        ctx.addRect(bounds)
        for spot in spotlights {
            guard let rect = spot.resizableRect else { continue }
            let radius = min(max(spot.style.cornerRadius, 0), min(rect.width, rect.height) / 2)
            ctx.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
        }
        ctx.setFillColor(NSColor.black.withAlphaComponent(min(max(first.style.opacity, 0.1), 0.9)).cgColor)
        ctx.fillPath(using: .evenOdd)
        ctx.restoreGState()
    }

    // MARK: Redaction

    private func drawRedaction(_ rect: CGRect, _ a: Annotation, base: CGImage, scale: CGFloat, _ zoom: CGFloat, _ ctx: CGContext) {
        let image = CGRect(x: 0, y: 0, width: CGFloat(base.width) / scale, height: CGFloat(base.height) / scale)
        let area = rect.intersection(image)
        guard area.width >= 1, area.height >= 1 else { return }
        if a.style.redaction == .blackout {
            let radius = min(2, min(area.width, area.height) / 2)
            layer(a, zoom, ctx) {
                ctx.addPath(CGPath(roundedRect: area, cornerWidth: radius, cornerHeight: radius, transform: nil))
                ctx.setFillColor(a.color.cgColor)
                ctx.fillPath()
            }
            return
        }
        guard let covered = redacted(area, a, base: base, scale: scale) else { return }
        ctx.saveGState()
        ctx.interpolationQuality = a.style.redaction == .pixelate ? .none : .high
        Self.drawImage(covered, in: area, ctx)
        ctx.restoreGState()
    }

    /// The area made unreadable. Pixelate averages it into coarse cells, each the mean of what it
    /// covers, so text turns into grey blocks too coarse to read back. Secure blur pixelates first
    /// and then blurs, so nothing of the original survives under the softening. Smooth blur is a
    /// plain gaussian, which looks nicer and suits faces and photos more than text.
    private func redacted(_ area: CGRect, _ a: Annotation, base: CGImage, scale: CGFloat) -> CGImage? {
        let key = RedactionKey(rect: area, base: ObjectIdentifier(base), mode: a.style.redaction, size: a.style.size)
        if let cached = redactionCache[a.id], cached.key == key { return cached.image }

        let pixels = CGRect(
            x: area.minX * scale, y: area.minY * scale, width: area.width * scale, height: area.height * scale
        ).integral
        guard let region = base.cropping(to: pixels) else { return nil }
        let strength = max(a.style.size, 2)
        let result: CGImage?
        switch a.style.redaction {
        case .pixelate, .blackout:
            let cell = max(strength, min(area.width, area.height) / 6) * scale
            result = Self.mosaic(region, cell: cell)
        case .blurSecure:
            let cell = max(strength * 0.6, 3) * scale
            guard let mosaic = Self.mosaic(region, cell: cell) else { return nil }
            let input = CIImage(cgImage: mosaic)
                .samplingNearest()
                .transformed(by: CGAffineTransform(
                    scaleX: CGFloat(region.width) / CGFloat(mosaic.width),
                    y: CGFloat(region.height) / CGFloat(mosaic.height)
                ))
            result = Self.blur(input, radius: cell * 0.9, extent: CGRect(x: 0, y: 0, width: region.width, height: region.height))
        case .blurSmooth:
            let input = CIImage(cgImage: region)
            result = Self.blur(input, radius: strength * scale * 0.9, extent: input.extent)
        }
        if let result { redactionCache[a.id] = (key, result) }
        return result
    }

    private static func mosaic(_ region: CGImage, cell: CGFloat) -> CGImage? {
        let columns = max(1, Int((CGFloat(region.width) / max(cell, 1)).rounded(.up)))
        let rows = max(1, Int((CGFloat(region.height) / max(cell, 1)).rounded(.up)))
        guard let small = CGContext(
            data: nil, width: columns, height: rows, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        small.interpolationQuality = .high
        small.draw(region, in: CGRect(x: 0, y: 0, width: columns, height: rows))
        return small.makeImage()
    }

    private static func blur(_ input: CIImage, radius: CGFloat, extent: CGRect) -> CGImage? {
        let blurred = input.clampedToExtent().applyingGaussianBlur(sigma: max(radius, 1) / 2).cropped(to: extent)
        return imageContext.createCGImage(blurred, from: extent)
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
