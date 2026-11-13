import AppKit
import SwiftUI

/// Where the Shotput icon sits in the menu bar, in screen coordinates. Set by the app delegate.
@MainActor
enum MenuBarAnchor {
    static var frame: () -> CGRect? = { nil }

    /// The point pins fly to: the icon, or the top centre of the screen when it is hidden.
    static func target(on screen: NSScreen?) -> CGRect {
        if let frame = frame(), frame.width > 0 { return frame }
        let screen = screen ?? NSScreen.main ?? NSScreen.screens[0]
        return CGRect(x: screen.frame.midX - 11, y: screen.frame.maxY - 22, width: 22, height: 22)
    }
}

/// The shelf that drops out of the menu bar while a preview is dragged. Let go over it to pin.
@MainActor
final class PinShelf {
    static let shared = PinShelf()

    private var panel: NSPanel?
    private let state = ShelfState()
    private var capture: Capture?

    func show(for capture: Capture) {
        guard panel == nil else { return }
        self.capture = capture
        state.phase = PinStore.shared.contains(capture) ? .alreadyPinned : .idle
        state.count = PinStore.shared.pins.count

        let size = CGSize(width: 320, height: 132)
        let anchor = MenuBarAnchor.target(on: capture.screen ?? NSScreen.underMouse)
        let screen = NSScreen.screens.first { $0.frame.intersects(anchor) } ?? NSScreen.main ?? NSScreen.screens[0]
        var origin = CGPoint(x: anchor.midX - size.width / 2, y: screen.visibleFrame.maxY - size.height - 8)
        origin.x = min(max(origin.x, screen.visibleFrame.minX + 8), screen.visibleFrame.maxX - size.width - 8)
        let frame = CGRect(origin: origin, size: size)

        let panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .popUpMenu
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        let drop = ShelfDropView(frame: CGRect(origin: .zero, size: size))
        drop.state = state
        drop.onDrop = { [weak self] in self?.pinDragged() ?? false }
        let host = NSHostingView(rootView: ShelfView(state: state))
        host.frame = drop.bounds
        host.autoresizingMask = [.width, .height]
        drop.addSubview(host)
        panel.contentView = drop
        self.panel = panel

        // Drops down out of the menu bar, the way the menu itself would.
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        panel.alphaValue = 0
        panel.setFrame(reduceMotion ? frame : frame.offsetBy(dx: 0, dy: 14), display: true)
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.25, 1)
            panel.animator().alphaValue = 1
            panel.animator().setFrame(frame, display: true)
        }
    }

    func hide(after delay: TimeInterval = 0) {
        guard let panel else { return }
        self.panel = nil
        capture = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.16
                context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                panel.animator().alphaValue = 0
                panel.animator().setFrame(panel.frame.offsetBy(dx: 0, dy: 8), display: true)
            }, completionHandler: { panel.orderOut(nil) })
        }
    }

    private func pinDragged() -> Bool {
        guard let capture else { return false }
        guard PinStore.shared.pin(capture) else {
            state.phase = .alreadyPinned
            return false
        }
        state.count = PinStore.shared.pins.count
        state.phase = .pinned
        NotificationCenter.default.post(name: .shotputDidPin, object: nil)
        hide(after: 0.55)
        return true
    }
}

extension Notification.Name {
    static let shotputDidPin = Notification.Name("ShotputDidPin")
}

@MainActor
final class ShelfState: ObservableObject {
    enum Phase { case idle, targeted, pinned, alreadyPinned }
    @Published var phase = Phase.idle
    @Published var count = 0
}

/// AppKit drop target under the SwiftUI drawing, so the shelf takes the preview's file drag.
private final class ShelfDropView: NSView {
    var state: ShelfState?
    var onDrop: (() -> Bool)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        MainActor.assumeIsolated {
            guard state?.phase != .alreadyPinned else { return [] }
            state?.phase = .targeted
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
            return .copy
        }
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        MainActor.assumeIsolated { if state?.phase == .targeted { state?.phase = .idle } }
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        MainActor.assumeIsolated { onDrop?() ?? false }
    }
}

private struct ShelfView: View {
    @ObservedObject var state: ShelfState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isTargeted: Bool { state.phase == .targeted }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.clear)
                .glassEffect(.regular.tint(isTargeted ? Palette.accent.color.opacity(0.22) : .clear), in: .rect(cornerRadius: 22))
            DotGrid()
                .opacity(isTargeted ? 0.5 : 0.28)
                .mask(RoundedRectangle(cornerRadius: 22, style: .continuous).padding(10))
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                .foregroundStyle(isTargeted ? Palette.accent.color : Color.primary.opacity(0.22))
                .padding(10)

            VStack(spacing: 4) {
                Group {
                    switch state.phase {
                    case .pinned: Icon.check.view(size: 22, weight: .semibold).foregroundStyle(.green)
                    case .alreadyPinned: Icon.pin.view(size: 18, weight: .semibold).foregroundStyle(.secondary)
                    default: Icon.pin.view(size: 18, weight: .semibold)
                        .foregroundStyle(isTargeted ? Palette.accent.color : .primary)
                        .rotationEffect(.degrees(isTargeted ? -18 : 0))
                    }
                }
                .frame(height: 26)
                .transition(.scale(scale: 0.6).combined(with: .opacity))
                Text(title)
                    .font(.headline)
                    .contentTransition(.opacity)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .scaleEffect(isTargeted && !reduceMotion ? 1.03 : 1)
        .animation(.spring(duration: 0.28, bounce: 0.3), value: state.phase)
        .padding(4)
    }

    private var title: String {
        switch state.phase {
        case .idle: L("Drop to pin")
        case .targeted: L("Let go to pin")
        case .pinned: L("Pinned")
        case .alreadyPinned: L("Already pinned")
        }
    }

    private var subtitle: String {
        switch state.phase {
        case .pinned: "In the menu bar, \(state.count) of \(PinStore.limit)"
        case .alreadyPinned: L("It’s in the menu bar")
        default: state.count >= PinStore.limit ? "The oldest of \(PinStore.limit) pins makes room" : "Keeps up to \(PinStore.limit) in the menu bar"
        }
    }
}

private struct DotGrid: View {
    var body: some View {
        Canvas { context, size in
            let step: CGFloat = 9
            var y = step / 2
            while y < size.height {
                var x = step / 2
                while x < size.width {
                    context.fill(Path(ellipseIn: CGRect(x: x - 0.9, y: y - 0.9, width: 1.8, height: 1.8)), with: .color(.primary))
                    x += step
                }
                y += step
            }
        }
    }
}
