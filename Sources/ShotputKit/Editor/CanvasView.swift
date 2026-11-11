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
        case pen(id: UUID)
        case crop(anchor: CGPoint)
    }

    let model: EditorModel
    var onDone: (() -> Void)?

    private let renderer = AnnotationRenderer()
    private let baseView = NSView()
    private let marks = MarkView()
    private var drag = Drag.none
    private var cropRect: CGRect?
    private var clickedAreaMark: UUID?
    private var textEditor: NSTextView?
    private var editing: (id: UUID?, origin: CGPoint, weight: Weight, color: InkColor, filled: Bool)?
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
        marks.frame = bounds
        if baseView.layer?.contents as AnyObject? !== model.base {
            baseView.layer?.contents = model.base
        }
        layer?.shadowPath = CGPath(rect: bounds, transform: nil)
        marks.needsDisplay = true
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    // MARK: Drawing

    private func drawMarks(_ ctx: CGContext) {
        let visible = model.annotations.filter { $0.id != editing?.id }
        renderer.draw(visible, base: model.base, scale: model.scale, zoom: zoom, in: ctx)
        drawSelection(ctx)
        drawCrop(ctx)
    }

    private func drawSelection(_ ctx: CGContext) {
        guard let selected = model.selected, selected.id != editing?.id else { return }
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
        guard let cropRect else { return }
        ctx.saveGState()
        ctx.addRect(imageBounds)
        ctx.addRect(cropRect)
        ctx.setFillColor(NSColor.black.withAlphaComponent(0.45).cgColor)
        ctx.fillPath(using: .evenOdd)
        ctx.setStrokeColor(.white)
        ctx.setLineWidth(1 / zoom)
        ctx.stroke(cropRect)
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
            } else if let rect = selected.resizableRect {
                let corners = rect.corners
                if let index = corners.firstIndex(where: { p.distance(to: $0) <= reach }) {
                    drag = .rect(id: selected.id, anchor: corners[(index + 2) % 4], creating: false)
                    return
                }
            }
        }

        clickedAreaMark = nil
        if model.tool != .crop, let hit = model.annotations.last(where: { $0.hitTest(p, tolerance: 6 / zoom) }) {
            // Solid marks only grab by their edge, or once selected. Otherwise nothing could be
            // drawn or typed on top of a redaction or highlight. A plain click inside still selects.
            let grabs = !hit.coversArea || hit.id == model.selectedID || hit.hitsOutline(p, tolerance: 6 / zoom)
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

        switch model.tool {
        case .crop:
            cropRect = nil
            drag = .crop(anchor: start)
        case .text:
            let pad = TextMetrics.padding(model.weight)
            let lineHeight = TextMetrics.textSize("", model.weight).height
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
        case .rectangle:
            drag = .rect(id: create(.rectangle(CGRect(origin: p, size: .zero))), anchor: p, creating: true)
        case .ellipse:
            drag = .rect(id: create(.ellipse(CGRect(origin: p, size: .zero))), anchor: p, creating: true)
        case .highlight:
            drag = .rect(id: create(.highlight(CGRect(origin: p, size: .zero))), anchor: p, creating: true)
        case .redact:
            drag = .rect(id: create(.redact(CGRect(origin: p, size: .zero))), anchor: p, creating: true)
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
        case let .endpoint(id, movesStart, _):
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
                return annotation.withEndpoints(from: movesStart ? p : fixed, to: movesStart ? fixed : p)
            }
        case let .pen(id):
            model.replace(id) { annotation in
                guard case var .pen(points) = annotation.kind,
                      let last = points.last, last.distance(to: raw) >= 1.5 / zoom else { return annotation }
                points.append(raw)
                var copy = annotation
                copy.kind = .pen(points)
                return copy
            }
        case let .crop(anchor):
            cropRect = CGRect(from: anchor, to: raw.clamped(to: imageBounds))
            marks.needsDisplay = true
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
            if case let .pen(points)? = model.annotations.first(where: { $0.id == id })?.kind, points.count < 2 {
                model.discardGesture()
                model.selectedID = clickedAreaMark
            }
        case .crop:
            if let rect = cropRect?.integral, rect.width >= 8, rect.height >= 8 {
                model.crop(to: rect)
            }
            cropRect = nil
            marks.needsDisplay = true
        default:
            break
        }
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

    // MARK: Keyboard

    override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard modifiers.isDisjoint(with: [.command, .control, .option]) else {
            super.keyDown(with: event)
            return
        }
        switch event.keyCode {
        case 51, 117:
            model.deleteSelected()
        case 53:
            cropRect = nil
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
            if let tool = Tool.allCases.first(where: { $0.key == character }) {
                model.setTool(tool)
            } else if let digit = character.wholeNumberValue, let color = InkColor(rawValue: digit - 1) {
                model.setColor(color)
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
        let weight = existing?.weight ?? model.weight
        let color = existing?.color ?? model.color
        let filled = existing?.filled ?? model.make(.text(origin: origin, string: "")).filled
        editing = (existing?.id, origin, weight, color, filled)

        let editor = NSTextView(frame: .zero)
        editor.delegate = self
        editor.isRichText = false
        editor.allowsUndo = true
        editor.font = TextMetrics.font(weight)
        editor.textColor = filled ? color.onInk : color.nsColor
        editor.insertionPointColor = filled ? color.onInk : color.nsColor
        editor.drawsBackground = false
        editor.textContainerInset = TextMetrics.padding(weight)
        editor.textContainer?.lineFragmentPadding = 0
        editor.textContainer?.widthTracksTextView = false
        editor.textContainer?.containerSize = CGSize(width: 10_000, height: 10_000)
        editor.isVerticallyResizable = false
        editor.isHorizontallyResizable = false
        editor.wantsLayer = true
        editor.layer?.backgroundColor = filled ? color.cgColor : NSColor.clear.cgColor
        editor.layer?.cornerRadius = min(weight.fontSize * 0.45, 100)
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
        var frame = TextMetrics.frame(origin: editing.origin, string: textEditor.string, weight: editing.weight)
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
            let annotation = Annotation(
                kind: .text(origin: editing.origin, string: string),
                color: editing.color, weight: editing.weight, filled: editing.filled
            )
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
