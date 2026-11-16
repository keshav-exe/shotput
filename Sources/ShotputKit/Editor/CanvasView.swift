import AppKit
import Combine

/// The editing surface. The screenshot lives in a GPU-backed layer and the marks are drawn in a
/// transparent view above it, so dragging a mark never redraws the screenshot.
final class CanvasView: NSView, NSTextViewDelegate, NSMenuItemValidation {
    private enum Drag {
        case none
        case move(id: UUID, last: CGPoint)
        case rect(id: UUID, anchor: CGPoint, creating: Bool)
        case endpoint(id: UUID, movesStart: Bool, creating: Bool)
        case bend(id: UUID)
        case pen(id: UUID)
        case marker(id: UUID, start: CGPoint)
        case cropNew(anchor: CGPoint)
        case cropMove(start: CGPoint, original: CGRect)
        case cropResize(handle: CropHandle, original: CGRect)
    }

    /// One of the crop box's eight handles: -1, 0, or 1 along each axis.
    private struct CropHandle {
        let x: Int
        let y: Int

        static let all: [CropHandle] = [(-1, -1), (0, -1), (1, -1), (1, 0), (1, 1), (0, 1), (-1, 1), (-1, 0)]
            .map { CropHandle(x: $0.0, y: $0.1) }

        func point(in rect: CGRect) -> CGPoint {
            CGPoint(x: rect.midX + CGFloat(x) * rect.width / 2, y: rect.midY + CGFloat(y) * rect.height / 2)
        }
    }

    let model: EditorModel
    var onDone: (() -> Void)?
    /// Esc with nothing left to clear.
    var onEscape: (() -> Void)?

    private let renderer = AnnotationRenderer()
    private let baseView = NSView()
    /// Highlighter strokes, multiplied into the screenshot below by Core Animation so text under
    /// them stays dark, the way ink from a real highlighter does.
    private let markers = MarkView()
    private let marks = MarkView()
    private var drag = Drag.none
    private var clickedAreaMark: UUID?
    private var textEditor: NSTextView?
    private var editing: (id: UUID?, origin: CGPoint, style: MarkStyle)?
    private var edges: (base: ObjectIdentifier, xs: [CGFloat], ys: [CGFloat])?
    private var lastTool: Tool?
    private var subscriptions = Set<AnyCancellable>()

    init(model: EditorModel) {
        self.model = model
        super.init(frame: CGRect(origin: .zero, size: model.size))
        wantsLayer = true
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.14
        layer?.shadowRadius = 14
        layer?.shadowOffset = CGSize(width: 0, height: -4)

        baseView.wantsLayer = true
        baseView.layer?.contentsGravity = .resize
        baseView.layer?.magnificationFilter = .nearest
        baseView.layer?.minificationFilter = .trilinear
        addSubview(baseView)

        markers.wantsLayer = true
        markers.layerUsesCoreImageFilters = true
        markers.layer?.compositingFilter = CIFilter(name: "CIMultiplyBlendMode")
        markers.draw = { [unowned self] ctx in self.drawMarkers(ctx) }
        addSubview(markers)

        marks.draw = { [unowned self] ctx in self.drawMarks(ctx) }
        addSubview(marks)
        syncWithModel()

        model.objectWillChange
            .sink { [weak self] in DispatchQueue.main.async { self?.syncWithModel() } }
            .store(in: &subscriptions)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    private var zoom: CGFloat { enclosingScrollView?.magnification ?? 1 }
    private var imageBounds: CGRect { CGRect(origin: .zero, size: model.size) }

    private func syncWithModel() {
        if frame.size != model.size {
            setFrameSize(model.size)
            enclosingScrollView?.reflectScrolledClipView(enclosingScrollView!.contentView)
        }
        baseView.frame = bounds
        markers.frame = bounds
        marks.frame = bounds
        if baseView.layer?.contents as AnyObject? !== model.base {
            baseView.layer?.contents = model.base
        }
        layer?.shadowPath = CGPath(rect: bounds, transform: nil)
        if lastTool != model.tool {
            lastTool = model.tool
            window?.invalidateCursorRects(for: self)
        }
        marks.needsDisplay = true
        markers.needsDisplay = true
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: model.tool == .select && model.crop == nil ? .arrow : .crosshair)
    }

    // MARK: Drawing

    private func drawMarkers(_ ctx: CGContext) {
        renderer.draw(model.annotations, base: model.base, scale: model.scale, zoom: zoom, in: ctx, pass: .markers)
    }

    private func drawMarks(_ ctx: CGContext) {
        let visible = model.annotations.filter { $0.id != editing?.id }
        renderer.draw(visible, base: model.base, scale: model.scale, zoom: zoom, in: ctx, pass: .marks)
        drawSelection(ctx)
        drawCrop(ctx)
    }

    private func drawSelection(_ ctx: CGContext) {
        guard model.crop == nil, let selected = model.selected, selected.id != editing?.id else { return }
        let unit = 1 / zoom
        let accent = Palette.accent.cgColor
        ctx.saveGState()
        ctx.setStrokeColor(accent)
        ctx.setLineWidth(unit)

        func handle(_ p: CGPoint) {
            let r = 4.5 * unit
            let circle = CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)
            ctx.saveGState()
            ctx.setShadow(offset: CGSize(width: 0, height: -0.5), blur: 2, color: NSColor.black.withAlphaComponent(0.3).cgColor)
            ctx.setFillColor(.white)
            ctx.fillEllipse(in: circle)
            ctx.restoreGState()
            ctx.setLineWidth(1.5 * unit)
            ctx.strokeEllipse(in: circle)
        }

        if let ends = selected.endpoints {
            handle(ends.from)
            handle(ends.to)
            // The bend handle is smaller and filled, so it reads as "shape this" rather than "move an end".
            if let middle = selected.bendHandle, ends.from.distance(to: ends.to) > 28 / zoom {
                let r = 3.5 * unit
                let dot = CGRect(x: middle.x - r, y: middle.y - r, width: r * 2, height: r * 2)
                ctx.saveGState()
                ctx.setShadow(offset: CGSize(width: 0, height: -0.5), blur: 2, color: NSColor.black.withAlphaComponent(0.3).cgColor)
                ctx.setFillColor(selected.bend == nil ? .white : accent)
                ctx.fillEllipse(in: dot)
                ctx.restoreGState()
                ctx.setLineWidth(1.5 * unit)
                ctx.setStrokeColor(selected.bend == nil ? accent : .white)
                ctx.strokeEllipse(in: dot)
            }
        } else if let rect = selected.resizableRect {
            ctx.stroke(rect)
            rect.corners.forEach(handle)
        } else {
            let outline = selected.frame.insetBy(dx: -4 * unit, dy: -4 * unit)
            ctx.setLineDash(phase: 0, lengths: [4 * unit, 3 * unit])
            ctx.addPath(CGPath(roundedRect: outline, cornerWidth: 4 * unit, cornerHeight: 4 * unit, transform: nil))
            ctx.strokePath()
        }
        ctx.restoreGState()
    }

    private func drawCrop(_ ctx: CGContext) {
        guard let box = model.crop?.rect else { return }
        let unit = 1 / zoom
        ctx.saveGState()
        ctx.addRect(imageBounds.insetBy(dx: -2000, dy: -2000))
        ctx.addRect(box)
        ctx.setFillColor(NSColor.black.withAlphaComponent(0.5).cgColor)
        ctx.fillPath(using: .evenOdd)

        // Rule of thirds.
        ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.45).cgColor)
        ctx.setLineWidth(unit)
        for i in 1 ... 2 {
            let x = box.minX + box.width * CGFloat(i) / 3
            let y = box.minY + box.height * CGFloat(i) / 3
            ctx.strokeLineSegments(between: [CGPoint(x: x, y: box.minY), CGPoint(x: x, y: box.maxY),
                                             CGPoint(x: box.minX, y: y), CGPoint(x: box.maxX, y: y)])
        }
        ctx.setStrokeColor(.white)
        ctx.stroke(box, width: unit)

        // Corner brackets and edge bars, drawn just inside the box so they stay on the image.
        let arm = min(18 * unit, box.width / 3, box.height / 3)
        let thick = 3 * unit
        ctx.setShadow(offset: .zero, blur: 3, color: NSColor.black.withAlphaComponent(0.45).cgColor)
        ctx.setFillColor(.white)
        for handle in CropHandle.all {
            let p = handle.point(in: box)
            if handle.x != 0, handle.y != 0 {
                let sx = CGFloat(-handle.x), sy = CGFloat(-handle.y)
                ctx.fill(CGRect(x: min(p.x, p.x + sx * arm), y: min(p.y, p.y + sy * thick), width: arm, height: thick))
                ctx.fill(CGRect(x: min(p.x, p.x + sx * thick), y: min(p.y, p.y + sy * arm), width: thick, height: arm))
            } else if handle.x == 0 {
                let sy = CGFloat(-handle.y)
                ctx.fill(CGRect(x: p.x - arm / 2, y: min(p.y, p.y + sy * thick), width: arm, height: thick))
            } else {
                let sx = CGFloat(-handle.x)
                ctx.fill(CGRect(x: min(p.x, p.x + sx * thick), y: p.y - arm / 2, width: thick, height: arm))
            }
        }
        ctx.restoreGState()
    }

    // MARK: Mouse

    override func mouseDown(with event: NSEvent) {
        if textEditor != nil {
            commitText()
            return
        }
        window?.makeFirstResponder(self)
        let p = convert(event.locationInWindow, from: nil)

        if let box = model.crop?.rect {
            let reach = 10 / zoom
            if let handle = CropHandle.all.first(where: { $0.point(in: box).distance(to: p) <= reach }) {
                drag = .cropResize(handle: handle, original: box)
            } else if box.contains(p) {
                drag = .cropMove(start: p, original: box)
            } else {
                drag = .cropNew(anchor: snapped(p.clamped(to: imageBounds), event))
            }
            return
        }

        model.beginGesture()

        if let selected = model.selected {
            let reach = 9 / zoom
            if let ends = selected.endpoints {
                if p.distance(to: ends.to) <= reach {
                    drag = .endpoint(id: selected.id, movesStart: false, creating: false)
                    return
                }
                if p.distance(to: ends.from) <= reach {
                    drag = .endpoint(id: selected.id, movesStart: true, creating: false)
                    return
                }
                if let middle = selected.bendHandle, p.distance(to: middle) <= reach {
                    // Double click a bent line to straighten it again.
                    if event.clickCount == 2 {
                        model.replace(selected.id) { var copy = $0; copy.bend = nil; return copy }
                        return
                    }
                    drag = .bend(id: selected.id)
                    return
                }
            } else if let rect = selected.resizableRect {
                let corners = rect.corners
                if let index = corners.firstIndex(where: { p.distance(to: $0) <= reach }) {
                    drag = .rect(id: selected.id, anchor: corners[(index + 2) % 4], creating: false)
                    return
                }
            }
        }

        clickedAreaMark = nil
        if let hit = model.annotations.last(where: { $0.hitTest(p, tolerance: 6 / zoom) }) {
            // Solid marks only grab by their edge, or once selected. Otherwise nothing could be
            // drawn or typed on top of a redaction or highlight. A plain click inside still
            // selects, and the select tool grabs anything.
            let grabs = model.tool == .select || !hit.coversArea || hit.id == model.selectedID
                || hit.hitsOutline(p, tolerance: 6 / zoom)
            if grabs {
                model.selectedID = hit.id
                if event.clickCount == 2, case let .text(origin, _) = hit.kind {
                    beginTextEditing(at: origin, existing: hit)
                } else {
                    drag = .move(id: hit.id, last: p)
                }
                return
            }
            clickedAreaMark = hit.id
        }

        model.selectedID = nil
        let start = p.clamped(to: imageBounds)

        func create(_ kind: Annotation.Kind) -> UUID {
            let annotation = model.make(kind)
            model.update { $0.append(annotation) }
            return annotation.id
        }
        let zero = CGRect(origin: start, size: .zero)

        switch model.tool {
        case .select:
            model.selectedID = clickedAreaMark
        case .text:
            let style = model.style(for: .text)
            let pad = TextMetrics.padding(style)
            let lineHeight = TextMetrics.textSize("", style).height
            beginTextEditing(at: CGPoint(x: p.x - pad.width, y: p.y - pad.height - lineHeight / 2), existing: nil)
        case .counter:
            let id = create(.counter(center: p, number: model.nextCounter))
            model.selectedID = id
            drag = .move(id: id, last: p)
        case .pen:
            drag = .pen(id: create(.pen([p])))
        case .arrow:
            drag = .endpoint(id: create(.arrow(from: p, to: p)), movesStart: false, creating: true)
        case .line:
            drag = .endpoint(id: create(.line(from: p, to: p)), movesStart: false, creating: true)
        case .rectangle, .filledRectangle:
            drag = .rect(id: create(.rectangle(zero)), anchor: start, creating: true)
        case .ellipse:
            drag = .rect(id: create(.ellipse(zero)), anchor: start, creating: true)
        case .highlight:
            drag = .marker(id: create(.highlight([p])), start: p)
        case .redact:
            drag = .rect(id: create(.redact(zero)), anchor: start, creating: true)
        case .spotlight:
            drag = .rect(id: create(.spotlight(zero)), anchor: start, creating: true)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let raw = convert(event.locationInWindow, from: nil)
        let constrain = event.modifierFlags.contains(.shift)
        autoscroll(with: event)

        switch drag {
        case .none:
            break
        case let .move(id, last):
            let delta = raw - last
            model.replace(id) { $0.translated(by: delta) }
            drag = .move(id: id, last: raw)
        case let .rect(id, anchor, _):
            var p = raw
            if constrain {
                let side = max(abs(p.x - anchor.x), abs(p.y - anchor.y))
                p = CGPoint(
                    x: anchor.x + (p.x < anchor.x ? -side : side),
                    y: anchor.y + (p.y < anchor.y ? -side : side)
                )
            }
            model.replace(id) { $0.withRect(CGRect(from: anchor, to: p)) }
        case let .endpoint(id, movesStart, creating):
            model.replace(id) { annotation in
                guard let ends = annotation.endpoints else { return annotation }
                let fixed = movesStart ? ends.to : ends.from
                var p = raw
                if constrain {
                    // Snap to 45 degree steps.
                    let delta = raw - fixed
                    let step = CGFloat.pi / 4
                    let angle = (atan2(delta.y, delta.x) / step).rounded() * step
                    p = fixed + CGPoint(x: cos(angle), y: sin(angle)) * delta.length
                }
                let moved = annotation.withEndpoints(from: movesStart ? p : fixed, to: movesStart ? fixed : p)
                // A new curved arrow keeps its arc in proportion as it is drawn out.
                return creating && annotation.style.curved ? moved.withAutomaticBend() : moved
            }
        case let .bend(id):
            model.replace(id) { $0.bent(through: raw) }
        case let .pen(id):
            model.replace(id) { annotation in
                guard case var .pen(points) = annotation.kind,
                      let last = points.last, last.distance(to: raw) >= 1.5 / zoom else { return annotation }
                points.append(raw)
                var copy = annotation
                copy.kind = .pen(points)
                return copy
            }
        case let .marker(id, start):
            model.replace(id) { annotation in
                guard case var .highlight(points) = annotation.kind else { return annotation }
                if constrain {
                    // Shift draws it straight, level when it's nearly level.
                    points = [start, Self.leveled(from: start, to: raw)]
                } else {
                    guard let last = points.last, last.distance(to: raw) >= 1.5 / zoom else { return annotation }
                    points.append(raw)
                }
                var copy = annotation
                copy.kind = .highlight(points)
                return copy
            }
        case let .cropNew(anchor):
            let p = snapped(raw.clamped(to: imageBounds), event)
            model.crop?.rect = fitted(CGRect(from: anchor, to: p), anchor: anchor, toward: p)
        case let .cropMove(start, original):
            var rect = original.offsetBy(dx: raw.x - start.x, dy: raw.y - start.y)
            rect.origin.x = min(max(rect.minX, 0), imageBounds.width - rect.width)
            rect.origin.y = min(max(rect.minY, 0), imageBounds.height - rect.height)
            if snaps(event), let edges = edgeCandidates() {
                let reach = 8 / zoom
                let left = EdgeFinder.snap(rect.minX, to: edges.xs, reach: reach)
                let right = EdgeFinder.snap(rect.maxX, to: edges.xs, reach: reach)
                rect.origin.x += left != rect.minX ? left - rect.minX : right - rect.maxX
                let top = EdgeFinder.snap(rect.minY, to: edges.ys, reach: reach)
                let bottom = EdgeFinder.snap(rect.maxY, to: edges.ys, reach: reach)
                rect.origin.y += top != rect.minY ? top - rect.minY : bottom - rect.maxY
            }
            model.crop?.rect = rect
        case let .cropResize(handle, original):
            let p = snapped(raw.clamped(to: imageBounds), event)
            model.crop?.rect = resized(original, handle: handle, to: p)
        }
    }

    override func mouseUp(with event: NSEvent) {
        defer { drag = .none }
        switch drag {
        case let .rect(id, _, creating) where creating:
            finishCreating(id) { $0.frame.width >= 4 || $0.frame.height >= 4 }
        case let .endpoint(id, _, creating) where creating:
            finishCreating(id) { annotation in
                annotation.endpoints.map { $0.from.distance(to: $0.to) >= 6 } ?? false
            }
        case let .pen(id):
            guard case let .pen(points)? = model.annotations.first(where: { $0.id == id })?.kind else { break }
            if points.count < 2 {
                model.discardGesture()
                model.selectedID = clickedAreaMark
            } else if Settings.shared.recognizesShapes, let shape = ShapeRecognizer.recognize(points) {
                // A separate undo step, so ⌘Z brings the sketch back.
                model.beginGesture()
                model.replace(id) { var copy = $0; copy.kind = shape.kind; return copy }
                model.showToast("Made it a \(shape.name). ⌘Z keeps the sketch")
            }
        case let .marker(id, _):
            guard let annotation = model.annotations.first(where: { $0.id == id }),
                  case let .highlight(points) = annotation.kind else { break }
            let length = zip(points, points.dropFirst()).reduce(0) { $0 + $1.0.distance(to: $1.1) }
            if points.count < 2 || length < 3 {
                model.discardGesture()
                model.selectedID = clickedAreaMark
            } else if let tidy = Self.tidied(points, width: annotation.style.size) {
                model.replace(id) { var copy = $0; copy.kind = .highlight(tidy); return copy }
            }
        case .cropNew:
            // A click outside the box, not a drag, leaves the old box alone rather than a sliver.
            if let rect = model.crop?.rect, rect.width < 4 || rect.height < 4 {
                model.crop?.rect = imageBounds
            }
        default:
            break
        }
    }

    /// The end of a straight marker stroke, pulled level when it's within a few degrees of it.
    private static func leveled(from start: CGPoint, to end: CGPoint) -> CGPoint {
        let delta = end - start
        guard abs(delta.x) > 0, abs(delta.y) / abs(delta.x) < tan(8 * CGFloat.pi / 180) else { return end }
        return CGPoint(x: end.x, y: start.y)
    }

    /// A hand-drawn marker stroke that stayed close to a straight line becomes that line, and one
    /// that ran nearly level becomes level, centred on the stroke: a tidy band across the text.
    /// Nil leaves the stroke as drawn.
    private static func tidied(_ points: [CGPoint], width: CGFloat) -> [CGPoint]? {
        guard points.count > 2, let first = points.first, let last = points.last else { return nil }
        let chord = last - first
        guard chord.length > width else { return nil }
        let tolerance = max(width * 0.45, 3)
        guard points.allSatisfy({ $0.distance(toSegment: first, last) <= tolerance }) else { return nil }
        if abs(chord.y) / max(abs(chord.x), 0.001) < tan(8 * CGFloat.pi / 180) {
            let y = points.reduce(0) { $0 + $1.y } / CGFloat(points.count)
            return [CGPoint(x: first.x, y: y), CGPoint(x: last.x, y: y)]
        }
        return [first, last]
    }

    private func finishCreating(_ id: UUID, isValid: (Annotation) -> Bool) {
        guard let annotation = model.annotations.first(where: { $0.id == id }) else { return }
        if isValid(annotation) {
            model.selectedID = id
        } else {
            model.discardGesture()
            model.selectedID = clickedAreaMark
        }
    }

    // MARK: Crop geometry

    /// Snapping is on when the setting says so, and ⌘ flips it for the length of a drag.
    private func snaps(_ event: NSEvent) -> Bool {
        model.snapsToEdges != event.modifierFlags.contains(.command)
    }

    private func edgeCandidates() -> (xs: [CGFloat], ys: [CGFloat])? {
        let id = ObjectIdentifier(model.base)
        if edges?.base != id {
            let found = EdgeFinder.edges(in: model.base, scale: model.scale)
            edges = (id, found.xs + [0, model.size.width], found.ys + [0, model.size.height])
        }
        return edges.map { ($0.xs, $0.ys) }
    }

    private func snapped(_ p: CGPoint, _ event: NSEvent) -> CGPoint {
        guard snaps(event), let edges = edgeCandidates() else { return p }
        let reach = 8 / zoom
        return CGPoint(x: EdgeFinder.snap(p.x, to: edges.xs, reach: reach), y: EdgeFinder.snap(p.y, to: edges.ys, reach: reach))
    }

    private var cropRatio: CGFloat? { model.crop?.aspect.value(original: model.size) }

    /// A box from `anchor` toward `p`, held to the crop's shape and kept inside the image.
    private func fitted(_ rect: CGRect, anchor: CGPoint, toward p: CGPoint) -> CGRect {
        guard let ratio = cropRatio else { return rect.intersection(imageBounds) }
        let dx: CGFloat = p.x < anchor.x ? -1 : 1, dy: CGFloat = p.y < anchor.y ? -1 : 1
        let roomX = dx > 0 ? imageBounds.maxX - anchor.x : anchor.x
        let roomY = dy > 0 ? imageBounds.maxY - anchor.y : anchor.y
        var width = max(abs(p.x - anchor.x), abs(p.y - anchor.y) * ratio)
        width = min(width, roomX, roomY * ratio)
        let height = width / ratio
        return CGRect(from: anchor, to: CGPoint(x: anchor.x + dx * width, y: anchor.y + dy * height))
    }

    private func resized(_ original: CGRect, handle: CropHandle, to p: CGPoint) -> CGRect {
        var minX = original.minX, maxX = original.maxX, minY = original.minY, maxY = original.maxY
        if handle.x < 0 { minX = p.x } else if handle.x > 0 { maxX = p.x }
        if handle.y < 0 { minY = p.y } else if handle.y > 0 { maxY = p.y }
        let free = CGRect(x: min(minX, maxX), y: min(minY, maxY), width: max(abs(maxX - minX), 1), height: max(abs(maxY - minY), 1))
        guard let ratio = cropRatio else { return free.intersection(imageBounds) }

        if handle.x != 0, handle.y != 0 {
            // A corner: the opposite corner stays put.
            let anchor = CGPoint(x: handle.x < 0 ? original.maxX : original.minX, y: handle.y < 0 ? original.maxY : original.minY)
            return fitted(free, anchor: anchor, toward: p)
        }
        // An edge: the other side grows about the box's centre line.
        var rect = free
        if handle.x != 0 {
            rect.size.height = rect.width / ratio
            rect.origin.y = original.midY - rect.height / 2
        } else {
            rect.size.width = rect.height * ratio
            rect.origin.x = original.midX - rect.width / 2
        }
        if !imageBounds.contains(rect) {
            let clipped = rect.intersection(imageBounds)
            let scale = min(clipped.width / rect.width, clipped.height / rect.height)
            let size = CGSize(width: rect.width * scale, height: rect.height * scale)
            rect = CGRect(
                x: handle.x < 0 ? rect.maxX - size.width : handle.x > 0 ? rect.minX : original.midX - size.width / 2,
                y: handle.y < 0 ? rect.maxY - size.height : handle.y > 0 ? rect.minY : original.midY - size.height / 2,
                width: size.width, height: size.height
            )
            rect.origin.x = min(max(rect.minX, 0), imageBounds.width - rect.width)
            rect.origin.y = min(max(rect.minY, 0), imageBounds.height - rect.height)
        }
        return rect
    }

    // MARK: Keyboard

    override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard modifiers.isDisjoint(with: [.command, .control, .option]) else {
            super.keyDown(with: event)
            return
        }
        if model.crop != nil {
            switch event.keyCode {
            case 53: model.cancelCrop()
            case 36, 76: model.applyCrop()
            default: super.keyDown(with: event)
            }
            return
        }
        switch event.keyCode {
        case 51, 117:
            model.deleteSelected()
        case 53:
            if model.selectedID == nil {
                onEscape?()
                return
            }
            model.selectedID = nil
            marks.needsDisplay = true
        case 36, 76:
            onDone?()
        case 123 ... 126:
            guard let id = model.selectedID else { return }
            let step: CGFloat = modifiers.contains(.shift) ? 10 : 1
            let delta: CGPoint = switch event.keyCode {
            case 123: CGPoint(x: -step, y: 0)
            case 124: CGPoint(x: step, y: 0)
            case 125: CGPoint(x: 0, y: step)
            default: CGPoint(x: 0, y: -step)
            }
            model.beginGesture()
            model.replace(id) { $0.translated(by: delta) }
        default:
            guard let character = event.charactersIgnoringModifiers?.lowercased().first else { return }
            if character == "c" {
                model.beginCrop()
            } else if let tool = Tool.allCases.first(where: { $0.key == character }) {
                model.setTool(tool)
            } else if let digit = character.wholeNumberValue {
                model.setColor(Ink.palette[(digit + 9) % 10])
            } else {
                super.keyDown(with: event)
            }
        }
    }

    // MARK: Edit menu

    // Undo lives here rather than on the window controller because NSWindow answers undo: itself,
    // and would swallow it before the controller saw it.
    @objc func undo(_ sender: Any?) {
        if let textEditor { textEditor.undoManager?.undo() } else { model.undo() }
    }

    @objc func redo(_ sender: Any?) {
        if let textEditor { textEditor.undoManager?.redo() } else { model.redo() }
    }

    @objc func delete(_ sender: Any?) { model.deleteSelected() }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(undo(_:)): textEditor?.undoManager?.canUndo ?? model.canUndo
        case #selector(redo(_:)): textEditor?.undoManager?.canRedo ?? model.canRedo
        case #selector(delete(_:)): model.selectedID != nil
        default: true
        }
    }

    // MARK: Text editing

    private func beginTextEditing(at origin: CGPoint, existing: Annotation?) {
        let style = existing?.style ?? model.style(for: .text)
        editing = (existing?.id, origin, style)
        let pill = style.text == .pill

        let editor = NSTextView(frame: .zero)
        editor.delegate = self
        editor.isRichText = false
        editor.allowsUndo = true
        editor.font = TextMetrics.font(style)
        editor.textColor = pill ? style.color.onInk : style.color.nsColor
        editor.insertionPointColor = pill ? style.color.onInk : style.color.nsColor
        editor.drawsBackground = false
        editor.textContainerInset = TextMetrics.padding(style)
        editor.textContainer?.lineFragmentPadding = 0
        editor.textContainer?.widthTracksTextView = false
        editor.textContainer?.containerSize = CGSize(width: 10_000, height: 10_000)
        editor.isVerticallyResizable = false
        editor.isHorizontallyResizable = false
        editor.wantsLayer = true
        editor.layer?.backgroundColor = pill ? style.color.cgColor : NSColor.clear.cgColor
        editor.layer?.cornerRadius = pill ? min(style.size * 0.45, 100) : 0
        editor.focusRingType = .none
        if case let .text(_, string)? = existing?.kind { editor.string = string }

        textEditor = editor
        addSubview(editor)
        sizeEditorToFit()
        window?.makeFirstResponder(editor)
        editor.selectAll(nil)
        marks.needsDisplay = true
    }

    private func sizeEditorToFit() {
        guard let textEditor, let editing else { return }
        var frame = TextMetrics.frame(origin: editing.origin, string: textEditor.string, style: editing.style)
        frame.size.width += 3 // room for the caret
        textEditor.frame = frame
    }

    func textDidChange(_ notification: Notification) { sizeEditorToFit() }

    func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)):
            if NSApp.currentEvent?.modifierFlags.contains(.shift) == true {
                textView.insertNewlineIgnoringFieldEditor(nil)
            } else {
                commitText()
            }
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            commitText()
            return true
        default:
            return false
        }
    }

    func textDidEndEditing(_ notification: Notification) { commitText() }

    func commitText() {
        guard let editor = textEditor, let editing else { return }
        textEditor = nil
        self.editing = nil
        let string = editor.string.trimmingCharacters(in: .whitespacesAndNewlines)
        editor.delegate = nil
        editor.removeFromSuperview()

        if let id = editing.id {
            model.beginGesture()
            if string.isEmpty {
                model.update { $0.removeAll { $0.id == id } }
                model.selectedID = nil
            } else {
                model.replace(id) { var copy = $0; copy.kind = .text(origin: editing.origin, string: string); return copy }
            }
        } else if !string.isEmpty {
            let annotation = Annotation(kind: .text(origin: editing.origin, string: string), style: editing.style)
            model.perform { $0.append(annotation) }
            model.selectedID = annotation.id
        }
        marks.needsDisplay = true
        if window?.firstResponder !== self { window?.makeFirstResponder(self) }
    }
}

/// Transparent drawing surface for marks. Mouse events fall through to the canvas.
private final class MarkView: NSView {
    var draw: ((CGContext) -> Void)?

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        draw?(ctx)
    }
}
