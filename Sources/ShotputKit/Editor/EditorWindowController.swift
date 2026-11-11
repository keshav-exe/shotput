import AppKit
import Combine
import SwiftUI
import Vision

private extension NSToolbarItem.Identifier {
    static let tools = NSToolbarItem.Identifier("tools")
    static let recognizeText = NSToolbarItem.Identifier("recognizeText")
    static let save = NSToolbarItem.Identifier("save")
    static let copy = NSToolbarItem.Identifier("copy")
    static let done = NSToolbarItem.Identifier("done")
}

final class EditorWindowController: NSWindowController, NSWindowDelegate, NSToolbarDelegate {
    /// Space kept clear under the image for the floating style bar.
    private static let bottomReserve: CGFloat = 68
    private static let margin: CGFloat = 40
    private static let minimumContent = CGSize(width: 760, height: 460)

    let capture: Capture
    var onClose: ((EditorWindowController) -> Void)?

    let model: EditorModel
    let canvas: CanvasView
    private let scrollView = NSScrollView()
    private var toolGroup: NSToolbarItemGroup?
    private var fitsWindow = true
    private var subscriptions = Set<AnyCancellable>()

    init(capture: Capture) {
        self.capture = capture
        model = EditorModel(base: capture.image, scale: capture.scale)
        canvas = CanvasView(model: model)

        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: Self.minimumContent),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false
        )
        super.init(window: window)

        window.title = "Shotput"
        window.titleVisibility = .hidden
        window.backgroundColor = Palette.background
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.delegate = self
        window.contentMinSize = Self.minimumContent

        let toolbar = NSToolbar(identifier: "editor")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        window.toolbar = toolbar
        window.toolbarStyle = .unified

        buildContent(in: window)
        canvas.onDone = { [weak self] in self?.done(nil) }

        model.$tool
            .sink { [weak self] tool in self?.toolGroup?.selectedIndex = tool.rawValue }
            .store(in: &subscriptions)
        NotificationCenter.default.addObserver(
            self, selector: #selector(userMagnified), name: NSScrollView.didEndLiveMagnifyNotification, object: scrollView
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func buildContent(in window: NSWindow) {
        let content = NSView()
        window.contentView = content

        let clip = CenteringClipView()
        clip.bottomReserve = Self.bottomReserve
        clip.drawsBackground = false
        scrollView.contentView = clip
        scrollView.documentView = canvas
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.allowsMagnification = true
        scrollView.minMagnification = 0.1
        scrollView.maxMagnification = 16
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(scrollView)

        let bar = NSHostingView(rootView: StyleBar(model: model))
        bar.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(bar)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: content.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            bar.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            bar.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -Metrics.spacingS),
        ])
    }

    // MARK: Presentation

    /// Shows the editor. When the capture's on-screen position is known and there is room, the
    /// image opens exactly where it was captured, so the screenshot appears to lift into the editor.
    func present() {
        guard let window else { return }
        layOut()
        AppPresence.shared.windowDidOpen()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window.makeFirstResponder(canvas)
    }

    /// Sizes and places the window, then fits the image. Separate from `present` so the layout
    /// can be exercised without putting a window on screen.
    func layOut() {
        guard let window else { return }
        let screen = capture.screen ?? NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let chrome = window.frameRect(forContentRect: .zero).size
        let limit = CGSize(width: visible.width * 0.94 - chrome.width, height: visible.height * 0.94 - chrome.height)
        let image = model.size

        let content = CGSize(
            width: min(max(image.width + Self.margin * 2, Self.minimumContent.width), limit.width),
            height: min(max(image.height + Self.margin * 2 + Self.bottomReserve, Self.minimumContent.height), limit.height)
        )
        // Centre of the image area, measured from the bottom-left of the content rect.
        let imageCenter = CGPoint(x: content.width / 2, y: Self.bottomReserve + (content.height - Self.bottomReserve) / 2)
        let target = capture.screenRect?.center ?? CGPoint(x: visible.midX, y: visible.midY + Self.bottomReserve / 2)

        var frame = window.frameRect(forContentRect: CGRect(
            x: (target.x - imageCenter.x).rounded(), y: (target.y - imageCenter.y).rounded(),
            width: content.width, height: content.height
        ))
        frame.origin.x = min(max(frame.minX, visible.minX), visible.maxX - frame.width)
        frame.origin.y = min(max(frame.minY, visible.minY), visible.maxY - frame.height)
        window.setFrame(frame, display: false)
        window.layoutIfNeeded()
        zoomToFit()
    }

    private func zoomToFit() {
        let available = CGSize(
            width: scrollView.bounds.width - Self.margin * 2,
            height: scrollView.bounds.height - Self.margin * 2 - Self.bottomReserve
        )
        let image = model.size
        guard image.width > 0, image.height > 0, available.width > 0, available.height > 0 else { return }
        scrollView.magnification = min(1, available.width / image.width, available.height / image.height)
        fitsWindow = true
    }

    @objc private func userMagnified() { fitsWindow = false }

    func windowDidResize(_ notification: Notification) {
        if fitsWindow { zoomToFit() }
    }

    func windowWillClose(_ notification: Notification) {
        AppPresence.shared.windowDidClose()
        onClose?(self)
    }

    // MARK: Toolbar

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.tools, .flexibleSpace, .recognizeText, .save, .copy, .done]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(
        _ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        switch identifier {
        case .tools:
            let group = NSToolbarItemGroup(
                itemIdentifier: identifier,
                images: Tool.allCases.map { NSImage(systemSymbolName: $0.symbol, accessibilityDescription: $0.title) ?? NSImage() },
                selectionMode: .selectOne,
                labels: Tool.allCases.map(\.title),
                target: self, action: #selector(toolPicked(_:))
            )
            for (tool, item) in zip(Tool.allCases, group.subitems) {
                item.toolTip = "\(tool.title) (\(String(tool.key).uppercased()))"
            }
            group.selectedIndex = model.tool.rawValue
            group.label = "Tools"
            toolGroup = group
            return group
        case .recognizeText:
            return button(identifier, "Copy text", "text.viewfinder", #selector(copyRecognizedText(_:)),
                          tip: "Copy the text in this screenshot")
        case .save:
            return button(identifier, "Save", "square.and.arrow.down", #selector(saveDocument(_:)), tip: "Save (⌘S)")
        case .copy:
            return button(identifier, "Copy", "doc.on.doc", #selector(copy(_:)), tip: "Copy (⌘C)")
        case .done:
            let item = NSToolbarItem(itemIdentifier: identifier)
            item.title = "Done"
            item.label = "Done"
            item.toolTip = "Copy and close (Return)"
            item.style = .prominent
            item.target = self
            item.action = #selector(done(_:))
            return item
        default:
            return nil
        }
    }

    private func button(
        _ identifier: NSToolbarItem.Identifier, _ label: String, _ symbol: String, _ action: Selector, tip: String
    ) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.label = label
        item.toolTip = tip
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        item.isBordered = true
        item.target = self
        item.action = action
        return item
    }

    @objc private func toolPicked(_ sender: NSToolbarItemGroup) {
        guard let tool = Tool(rawValue: sender.selectedIndex) else { return }
        canvas.commitText()
        model.setTool(tool)
        window?.makeFirstResponder(canvas)
    }

    // MARK: Actions

    private func flattened() -> CGImage? {
        canvas.commitText()
        return AnnotationRenderer().flatten(
            base: model.base, scale: model.scale, annotations: model.annotations, outputScale: model.scale
        )
    }

    /// Flattens into the capture, so the preview, drag and drop, and "annotate last" all see the result.
    private func commitToCapture() -> Data? {
        guard let image = flattened() else { return nil }
        capture.replaceImage(image)
        return capture.png()?.data
    }

    @objc func copy(_ sender: Any?) {
        guard let png = commitToCapture() else { return }
        Output.copyToClipboard(png)
        model.showToast("Copied")
    }

    @objc func done(_ sender: Any?) {
        if let png = commitToCapture() { Output.copyToClipboard(png) }
        close()
    }

    @objc func saveDocument(_ sender: Any?) {
        guard let png = commitToCapture() else { return }
        Output.save(png, named: ImageCoding.timestampedName(for: capture.date), relativeTo: window) { [weak self] url in
            if let url { self?.model.showToast("Saved to \(url.deletingLastPathComponent().lastPathComponent)") }
        }
    }

    @objc func zoomImageIn(_ sender: Any?) { setMagnification(scrollView.magnification * 1.5) }
    @objc func zoomImageOut(_ sender: Any?) { setMagnification(scrollView.magnification / 1.5) }
    @objc func zoomImageToActualSize(_ sender: Any?) { setMagnification(1) }
    @objc func zoomImageToFit(_ sender: Any?) { zoomToFit() }

    private func setMagnification(_ value: CGFloat) {
        let visible = scrollView.documentVisibleRect
        scrollView.setMagnification(
            min(max(value, scrollView.minMagnification), scrollView.maxMagnification),
            centeredAt: CGPoint(x: visible.midX, y: visible.midY)
        )
        fitsWindow = false
    }

    /// Reads the text in the screenshot on this Mac and copies it.
    @objc func copyRecognizedText(_ sender: Any?) {
        let image = model.base
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            try? VNImageRequestHandler(cgImage: image).perform([request])
            let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
            DispatchQueue.main.async {
                guard let self else { return }
                if lines.isEmpty {
                    self.model.showToast("No text found")
                } else {
                    Output.copyToClipboard(text: lines.joined(separator: "\n"))
                    self.model.showToast(lines.count == 1 ? "Copied 1 line of text" : "Copied \(lines.count) lines of text")
                }
            }
        }
    }
}

/// Centres the image in the space above the style bar, and lets a zoomed image scroll clear of it.
private final class CenteringClipView: NSClipView {
    var bottomReserve: CGFloat = 0

    override func constrainBoundsRect(_ proposed: NSRect) -> NSRect {
        guard let document = documentView else { return super.constrainBoundsRect(proposed) }
        var rect = proposed
        let magnification = (superview as? NSScrollView)?.magnification ?? 1
        let size = document.frame.size
        let availableHeight = rect.height - bottomReserve / magnification

        rect.origin.x = size.width <= rect.width
            ? (size.width - rect.width) / 2
            : min(max(rect.origin.x, 0), size.width - rect.width)
        rect.origin.y = size.height <= availableHeight
            ? (size.height - availableHeight) / 2
            : min(max(rect.origin.y, 0), size.height - availableHeight)
        return rect
    }
}

/// Keeps editors alive while their windows are open.
final class EditorManager {
    static let shared = EditorManager()
    private var controllers: [EditorWindowController] = []

    func open(_ capture: Capture) {
        if let existing = controllers.first(where: { $0.capture === capture }) {
            existing.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let controller = EditorWindowController(capture: capture)
        controller.onClose = { [weak self] closed in
            // Released on the next turn, once AppKit has finished closing the window.
            DispatchQueue.main.async { self?.controllers.removeAll { $0 === closed } }
        }
        controllers.append(controller)
        controller.present()
    }
}
