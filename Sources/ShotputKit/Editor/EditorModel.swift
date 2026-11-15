import AppKit
import Combine

/// The editor's document: a base image, the marks on it, and the current drawing style.
final class EditorModel: ObservableObject {
    private struct Snapshot {
        let base: CGImage
        let annotations: [Annotation]
        let backdrop: AppliedBackdrop?
        let geometry: CGAffineTransform
    }

    /// The image as it was before a backdrop was added, and the backdrop around it now.
    struct AppliedBackdrop {
        let plain: CGImage
        let style: Backdrop.Style
    }

    /// Base image pixels per point.
    let scale: CGFloat

    @Published private(set) var base: CGImage
    @Published private(set) var annotations: [Annotation] = []
    @Published var selectedID: UUID? { didSet { adoptSelectionStyle() } }
    @Published private(set) var tool: Tool
    /// The style the toolbar shows: the selected mark's, or else the current tool's.
    @Published private(set) var style: MarkStyle
    @Published private(set) var canUndo = false
    @Published private(set) var canRedo = false
    @Published private(set) var toast: String?
    @Published private(set) var backdrop: AppliedBackdrop?
    /// Non-nil while the crop mode is open.
    @Published var crop: CropState?
    @Published var snapsToEdges: Bool {
        didSet { defaults.set(snapsToEdges, forKey: "editor.snapsToEdges") }
    }

    private var undoStack: [Snapshot] = []
    private var redoStack: [Snapshot] = []
    private var gesturePending = false
    private var gestureCheckpointed = false
    /// Consecutive style changes with the same key, like dragging through the colour picker,
    /// share one undo step.
    private var styleCoalesceKey: String?
    private var styles: [Tool: MarkStyle]
    private var toastDismissal: DispatchWorkItem?
    private let defaults = UserDefaults.standard

    /// The image as the editor opened it, for Revert to Original.
    private let original: (base: CGImage, backdrop: AppliedBackdrop?)
    private var originalBackdrop: AppliedBackdrop?
    /// Maps points on the original image to points on the current one, through every crop,
    /// turn, flip, resize, and backdrop since.
    private(set) var geometry = CGAffineTransform.identity

    init(base: CGImage, scale: CGFloat) {
        self.base = base
        self.scale = scale
        original = (base, nil)
        let tool = Tool(rawValue: defaults.string(forKey: "editor.toolName") ?? "") ?? .arrow
        self.tool = tool
        var styles: [Tool: MarkStyle] = [:]
        if let data = defaults.data(forKey: "editor.styles"),
           let saved = try? JSONDecoder().decode([String: MarkStyle].self, from: data) {
            for (name, style) in saved { if let tool = Tool(rawValue: name) { styles[tool] = style } }
        }
        self.styles = styles
        style = styles[tool] ?? .defaults(for: tool)
        snapsToEdges = defaults.object(forKey: "editor.snapsToEdges") as? Bool ?? true
    }

    /// Image size in points.
    var size: CGSize { CGSize(width: CGFloat(base.width) / scale, height: CGFloat(base.height) / scale) }
    var pixelSize: CGSize { CGSize(width: base.width, height: base.height) }
    var selected: Annotation? { annotations.first { $0.id == selectedID } }
    /// The tool whose style controls apply right now.
    var styleTool: Tool { selected?.tool ?? tool }
    var isEdited: Bool { canUndo }
    /// Whether anything has changed the image's shape or pixels since the editor opened.
    var canRevert: Bool { base !== original.base || !geometry.isIdentity }

    var nextCounter: Int {
        let numbers = annotations.compactMap { annotation -> Int? in
            if case let .counter(_, number) = annotation.kind { return number }
            return nil
        }
        return (numbers.max() ?? 0) + 1
    }

    func style(for tool: Tool) -> MarkStyle { styles[tool] ?? .defaults(for: tool) }

    func make(_ kind: Annotation.Kind) -> Annotation {
        Annotation(kind: kind, style: style(for: tool))
    }

    // MARK: Editing with undo

    /// Call at the start of a mouse gesture. The first `update` after it records one undo step,
    /// however many updates the drag goes on to make.
    func beginGesture() {
        gesturePending = true
        gestureCheckpointed = false
        styleCoalesceKey = nil
    }

    func update(_ body: (inout [Annotation]) -> Void) {
        if gesturePending {
            checkpoint()
            gesturePending = false
            gestureCheckpointed = true
        }
        body(&annotations)
    }

    func perform(_ body: (inout [Annotation]) -> Void) {
        beginGesture()
        update(body)
    }

    func replace(_ id: UUID, _ transform: (Annotation) -> Annotation) {
        update { list in
            guard let index = list.firstIndex(where: { $0.id == id }) else { return }
            list[index] = transform(list[index])
        }
    }

    /// Rolls back a gesture that turned out to be a no-op, such as a click with a shape tool.
    func discardGesture() {
        gesturePending = false
        guard gestureCheckpointed, let snapshot = undoStack.popLast() else { return }
        gestureCheckpointed = false
        annotations = snapshot.annotations
        canUndo = !undoStack.isEmpty
    }

    private func checkpoint() {
        undoStack.append(snapshot())
        redoStack.removeAll()
        canUndo = true
        canRedo = false
    }

    private func snapshot() -> Snapshot {
        Snapshot(base: base, annotations: annotations, backdrop: backdrop, geometry: geometry)
    }

    func undo() {
        guard let snapshot = undoStack.popLast() else { return }
        redoStack.append(self.snapshot())
        restore(snapshot)
    }

    func redo() {
        guard let snapshot = redoStack.popLast() else { return }
        undoStack.append(self.snapshot())
        restore(snapshot)
    }

    private func restore(_ snapshot: Snapshot) {
        styleCoalesceKey = nil
        base = snapshot.base
        annotations = snapshot.annotations
        backdrop = snapshot.backdrop
        geometry = snapshot.geometry
        selectedID = nil
        canUndo = !undoStack.isEmpty
        canRedo = !redoStack.isEmpty
        if crop != nil { crop?.rect = CGRect(origin: .zero, size: size) }
    }

    func deleteSelected() {
        guard let id = selectedID else { return }
        selectedID = nil
        perform { $0.removeAll { $0.id == id } }
    }

    // MARK: Image geometry

    /// Swaps the base image for one reshaped by `transform`, as one undo step, carrying the marks along.
    private func reshape(to image: CGImage, by transform: CGAffineTransform, keepsBackdrop: Bool = false) {
        beginGesture()
        update { list in list = list.map { $0.applying(transform) } }
        base = image
        geometry = geometry.concatenating(transform)
        // The new pixels own the backdrop now, so there is nothing left to swap.
        if !keepsBackdrop { backdrop = nil }
        selectedID = nil
    }

    func crop(to rect: CGRect) {
        let pixels = CGRect(
            x: rect.minX * scale, y: rect.minY * scale, width: rect.width * scale, height: rect.height * scale
        ).integral
        guard let cropped = base.cropping(to: pixels) else { return }
        reshape(to: cropped, by: CGAffineTransform(translationX: -pixels.minX / scale, y: -pixels.minY / scale))
    }

    func rotate(clockwise: Bool) {
        let old = size
        guard let turned = ImageOps.rotated(base, clockwise: clockwise) else { return }
        let t = clockwise
            ? CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: old.height, ty: 0)
            : CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: old.width)
        reshape(to: turned, by: t)
        if let box = crop?.rect { crop?.rect = box.applying(t).standardized }
    }

    func flip(horizontally: Bool) {
        let old = size
        guard let flipped = ImageOps.flipped(base, horizontally: horizontally) else { return }
        let t = horizontally
            ? CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: old.width, ty: 0)
            : CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: old.height)
        reshape(to: flipped, by: t)
        if let box = crop?.rect { crop?.rect = box.applying(t).standardized }
    }

    /// Scales the image to a new pixel size. Marks scale with it, so the result looks the same, smaller.
    func resample(toPixels target: CGSize) {
        let width = Int(target.width.rounded()), height = Int(target.height.rounded())
        guard width > 0, height > 0, width != base.width || height != base.height,
              let image = ImageOps.resampled(base, width: width, height: height) else { return }
        let t = CGAffineTransform(scaleX: CGFloat(width) / CGFloat(base.width), y: CGFloat(height) / CGFloat(base.height))
        reshape(to: image, by: t)
    }

    /// Back to the image as the editor opened it, with every mark put back where it was drawn.
    func revertToOriginal() {
        guard canRevert else { return }
        let back = geometry.inverted()
        beginGesture()
        update { list in list = list.map { $0.applying(back) } }
        base = original.base
        backdrop = originalBackdrop
        geometry = .identity
        selectedID = nil
        if crop != nil { crop?.rect = CGRect(origin: .zero, size: size) }
    }

    // MARK: Crop mode

    func beginCrop() {
        guard crop == nil else { return }
        selectedID = nil
        crop = CropState(rect: CGRect(origin: .zero, size: size))
    }

    func cancelCrop() { crop = nil }

    /// Crops to the box, scales the result if a smaller size was picked, and closes the crop mode.
    func applyCrop() {
        guard let state = crop else { return }
        crop = nil
        let box = state.rect.intersection(CGRect(origin: .zero, size: size))
        let whole = box.integral == CGRect(origin: .zero, size: size).integral
        if box.width >= 1, box.height >= 1, !whole { crop(to: box) }
        if state.outputScale < 0.999 {
            resample(toPixels: CGSize(width: CGFloat(base.width) * state.outputScale, height: CGFloat(base.height) * state.outputScale))
        }
    }

    /// Holds the crop box to a shape, keeping its centre and fitting it inside the image.
    func setCropAspect(_ aspect: AspectRatio) {
        guard var state = crop else { return }
        state.aspect = aspect
        if let ratio = aspect.value(original: size) {
            let bounds = CGRect(origin: .zero, size: size)
            var width = state.rect.width, height = width / ratio
            if height > state.rect.height { height = state.rect.height; width = height * ratio }
            // Use as much of the image as the shape allows when the box is small.
            if width < bounds.width * 0.5, height < bounds.height * 0.5 {
                width = bounds.width; height = width / ratio
                if height > bounds.height { height = bounds.height; width = height * ratio }
            }
            var rect = CGRect(x: state.rect.midX - width / 2, y: state.rect.midY - height / 2, width: width, height: height)
            rect.origin.x = min(max(rect.minX, 0), bounds.width - width)
            rect.origin.y = min(max(rect.minY, 0), bounds.height - height)
            state.rect = rect
        }
        crop = state
    }

    /// Sets the crop box's size in pixels, keeping its top-left corner where it can.
    func setCropPixelSize(width: CGFloat?, height: CGFloat?) {
        guard var state = crop else { return }
        let bounds = CGRect(origin: .zero, size: size)
        var w = (width ?? state.rect.width * scale) / scale
        var h = (height ?? state.rect.height * scale) / scale
        if let ratio = state.aspect.value(original: size) {
            if width != nil { h = w / ratio } else { w = h * ratio }
        }
        w = min(max(w, 1), bounds.width)
        h = min(max(h, 1), bounds.height)
        state.rect = CGRect(
            x: min(state.rect.minX, bounds.width - w), y: min(state.rect.minY, bounds.height - h), width: w, height: h
        )
        crop = state
    }

    // MARK: Backdrop

    /// Starts the editor on an image that was framed as it was captured.
    func adoptBackdrop(plain: CGImage, style: Backdrop.Style) {
        backdrop = AppliedBackdrop(plain: plain, style: style)
        originalBackdrop = backdrop
    }

    /// Puts the image on a backdrop, swaps the current one, or removes it with nil. Marks keep
    /// their place on the screenshot, and each change is one undo step.
    /// - Parameter coalesce: Folds into the previous step, for continuous changes like a slider.
    func setBackdrop(_ style: Backdrop.Style?, wallpaper: CGImage?, coalesce: Bool = false) {
        let plain = backdrop?.plain ?? base
        let oldPadding = backdrop?.style.padding ?? 0
        let newPadding = style?.padding ?? 0
        if !coalesce { checkpoint() }
        let shift = CGAffineTransform(translationX: newPadding - oldPadding, y: newPadding - oldPadding)
        annotations = annotations.map { $0.applying(shift) }
        geometry = geometry.concatenating(shift)
        if let style {
            base = Backdrop.compose(plain, scale: scale, style: style, wallpaper: wallpaper)
            backdrop = AppliedBackdrop(plain: plain, style: style)
        } else {
            base = plain
            backdrop = nil
        }
        selectedID = nil
    }

    // MARK: Style

    func setTool(_ newTool: Tool) {
        selectedID = nil
        tool = newTool
        style = style(for: newTool)
        defaults.set(newTool.rawValue, forKey: "editor.toolName")
    }

    /// Changes the current style, and the selected mark's with it.
    /// - Parameter coalesce: A key shared by a run of changes that should undo as one, such as
    ///   dragging through the colour picker.
    func setStyle(coalesce: String? = nil, _ change: (inout MarkStyle) -> Void) {
        change(&style)
        let target = styleTool
        var stored = style(for: target)
        change(&stored)
        styles[target] = stored
        saveStyles()

        guard let id = selectedID, let selected else { return }
        if coalesce == nil || coalesce != styleCoalesceKey {
            beginGesture()
        }
        let wasCurved = selected.style.curved
        replace(id) { annotation in
            var copy = annotation
            change(&copy.style)
            // The curved toggle reshapes the selected line or arrow, not only the next one.
            if copy.style.curved != wasCurved, copy.endpoints != nil {
                copy = copy.style.curved ? copy.withAutomaticBend() : { var c = copy; c.bend = nil; return c }()
            }
            return copy
        }
        styleCoalesceKey = coalesce
        // A rectangle switched to a solid fill becomes a filled rectangle, so follow it.
        if let now = self.selected, now.tool != selected.tool {
            style = now.style
        }
    }

    func setColor(_ ink: Ink, coalesce: String? = nil) {
        setStyle(coalesce: coalesce) { $0.color = ink }
    }

    private func saveStyles() {
        let named = Dictionary(uniqueKeysWithValues: styles.map { ($0.key.rawValue, $0.value) })
        if let data = try? JSONEncoder().encode(named) { defaults.set(data, forKey: "editor.styles") }
    }

    private func adoptSelectionStyle() {
        styleCoalesceKey = nil
        style = selected?.style ?? style(for: tool)
    }

    // MARK: Toast

    func showToast(_ message: String) {
        toastDismissal?.cancel()
        toast = message
        let dismissal = DispatchWorkItem { [weak self] in self?.toast = nil }
        toastDismissal = dismissal
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6, execute: dismissal)
    }
}
