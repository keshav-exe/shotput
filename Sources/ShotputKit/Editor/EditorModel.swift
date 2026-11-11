import AppKit
import Combine

/// The editor's document: a base image, the marks on it, and the current drawing style.
final class EditorModel: ObservableObject {
    private struct Snapshot {
        let base: CGImage
        let annotations: [Annotation]
        let backdrop: AppliedBackdrop?
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
    @Published private(set) var color: InkColor
    @Published private(set) var weight: Weight
    @Published private(set) var filled: Bool
    @Published private(set) var canUndo = false
    @Published private(set) var canRedo = false
    @Published private(set) var toast: String?
    @Published private(set) var backdrop: AppliedBackdrop?

    private var undoStack: [Snapshot] = []
    private var redoStack: [Snapshot] = []
    private var gesturePending = false
    private var gestureCheckpointed = false
    private var fillByTool: [Tool: Bool] = [.text: true]
    private var toastDismissal: DispatchWorkItem?
    private let defaults = UserDefaults.standard

    init(base: CGImage, scale: CGFloat) {
        self.base = base
        self.scale = scale
        let stored = Tool(rawValue: defaults.object(forKey: "editor.tool") as? Int ?? 0) ?? .arrow
        // Reopening on crop would make the first drag destructive.
        let tool = stored == .crop ? .arrow : stored
        self.tool = tool
        color = InkColor(rawValue: defaults.object(forKey: "editor.color") as? Int ?? 0) ?? .red
        weight = Weight(rawValue: defaults.object(forKey: "editor.weight") as? Int ?? 1) ?? .regular
        filled = tool == .text
    }

    /// Image size in points.
    var size: CGSize { CGSize(width: CGFloat(base.width) / scale, height: CGFloat(base.height) / scale) }
    var selected: Annotation? { annotations.first { $0.id == selectedID } }
    /// The tool whose style controls apply right now.
    var styleTool: Tool { selected?.tool ?? tool }
    var isEdited: Bool { canUndo }

    var nextCounter: Int {
        let numbers = annotations.compactMap { annotation -> Int? in
            if case let .counter(_, number) = annotation.kind { return number }
            return nil
        }
        return (numbers.max() ?? 0) + 1
    }

    func make(_ kind: Annotation.Kind) -> Annotation {
        var annotation = Annotation(kind: kind, color: color, weight: weight)
        annotation.filled = annotation.tool.supportsFill && (fillByTool[annotation.tool] ?? false)
        return annotation
    }

    // MARK: Editing with undo

    /// Call at the start of a mouse gesture. The first `update` after it records one undo step,
    /// however many updates the drag goes on to make.
    func beginGesture() {
        gesturePending = true
        gestureCheckpointed = false
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
        undoStack.append(Snapshot(base: base, annotations: annotations, backdrop: backdrop))
        redoStack.removeAll()
        canUndo = true
        canRedo = false
    }

    func undo() {
        guard let snapshot = undoStack.popLast() else { return }
        redoStack.append(Snapshot(base: base, annotations: annotations, backdrop: backdrop))
        restore(snapshot)
    }

    func redo() {
        guard let snapshot = redoStack.popLast() else { return }
        undoStack.append(Snapshot(base: base, annotations: annotations, backdrop: backdrop))
        restore(snapshot)
    }

    private func restore(_ snapshot: Snapshot) {
        base = snapshot.base
        annotations = snapshot.annotations
        backdrop = snapshot.backdrop
        selectedID = nil
        canUndo = !undoStack.isEmpty
        canRedo = !redoStack.isEmpty
    }

    func deleteSelected() {
        guard let id = selectedID else { return }
        selectedID = nil
        perform { $0.removeAll { $0.id == id } }
    }

    func crop(to rect: CGRect) {
        let pixels = CGRect(
            x: rect.minX * scale, y: rect.minY * scale, width: rect.width * scale, height: rect.height * scale
        ).integral
        guard let cropped = base.cropping(to: pixels) else { return }
        beginGesture()
        update { list in
            let shift = CGPoint(x: -pixels.minX / scale, y: -pixels.minY / scale)
            list = list.map { $0.translated(by: shift) }
        }
        base = cropped
        // The crop now owns the pixels, backdrop and all, so there is nothing left to swap.
        backdrop = nil
        selectedID = nil
    }

    /// Starts the editor on an image that was framed as it was captured.
    func adoptBackdrop(plain: CGImage, style: Backdrop.Style) {
        backdrop = AppliedBackdrop(plain: plain, style: style)
    }

    /// Puts the image on a backdrop, swaps the current one, or removes it with nil. Marks keep
    /// their place on the screenshot, and each change is one undo step.
    /// - Parameter coalesce: Folds into the previous step, for continuous changes like a slider.
    func setBackdrop(_ style: Backdrop.Style?, wallpaper: CGImage?, coalesce: Bool = false) {
        let plain = backdrop?.plain ?? base
        let oldPadding = backdrop?.style.padding ?? 0
        let newPadding = style?.padding ?? 0
        if !coalesce { checkpoint() }
        let shift = CGPoint(x: newPadding - oldPadding, y: newPadding - oldPadding)
        annotations = annotations.map { $0.translated(by: shift) }
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
        filled = fillByTool[newTool] ?? false
        defaults.set(newTool.rawValue, forKey: "editor.tool")
    }

    func setColor(_ newColor: InkColor) {
        color = newColor
        defaults.set(newColor.rawValue, forKey: "editor.color")
        if let id = selectedID {
            beginGesture()
            replace(id) { var copy = $0; copy.color = newColor; return copy }
        }
    }

    func setWeight(_ newWeight: Weight) {
        weight = newWeight
        defaults.set(newWeight.rawValue, forKey: "editor.weight")
        if let id = selectedID {
            beginGesture()
            replace(id) { var copy = $0; copy.weight = newWeight; return copy }
        }
    }

    func setFilled(_ newValue: Bool) {
        guard styleTool.supportsFill else { return }
        filled = newValue
        fillByTool[styleTool] = newValue
        if let id = selectedID {
            beginGesture()
            replace(id) { var copy = $0; copy.filled = newValue; return copy }
        }
    }

    private func adoptSelectionStyle() {
        guard let selected else { return }
        color = selected.color
        weight = selected.weight
        if selected.tool.supportsFill { filled = selected.filled }
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
