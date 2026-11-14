import AppKit
import SwiftUI

/// An optional stand-in for ⇧⌘5: Shotput's three captures beside macOS's own recorder. Picking
/// a capture starts it at once; picking a recording opens macOS's toolbar in that mode and leaves
/// the recording entirely to macOS. The bar takes the keyboard without bringing Shotput forward,
/// so 1 to 5, Return and Esc work over whatever app is in front.
@MainActor
final class CaptureBar {
    enum Mode: String, CaseIterable, Identifiable {
        case area, window, screen, recordArea, recordScreen

        var id: String { rawValue }
        var records: Bool { self == .recordArea || self == .recordScreen }
        var key: String { String((Self.allCases.firstIndex(of: self) ?? 0) + 1) }

        var title: String {
            switch self {
            case .area, .recordArea: "Area"
            case .window: "Window"
            case .screen, .recordScreen: "Screen"
            }
        }

        var help: String {
            switch self {
            case .area: "Capture an area"
            case .window: "Capture a window"
            case .screen: "Capture the screen"
            case .recordArea: "Record an area with macOS"
            case .recordScreen: "Record the screen with macOS"
            }
        }

        var icon: Icon {
            switch self {
            case .area, .recordArea: .areaDashed
            case .window: .window
            case .screen, .recordScreen: .screen
            }
        }

        @MainActor
        func perform() {
            switch self {
            case .area: CaptureCoordinator.shared.capture(.area)
            case .window: CaptureCoordinator.shared.capture(.window)
            case .screen: CaptureCoordinator.shared.capture(.screen)
            case .recordArea: SystemScreenshots.openToolbar(recording: .area)
            case .recordScreen: SystemScreenshots.openToolbar(recording: .screen)
            }
        }
    }

    static let shared = CaptureBar()

    private var panel: BarPanel?
    private var outsideClicks: Any?

    private var lastMode: Mode {
        get { Mode(rawValue: UserDefaults.standard.string(forKey: Settings.Key.captureBarMode) ?? "") ?? .area }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: Settings.Key.captureBarMode) }
    }

    func toggle() {
        panel == nil ? show() : close()
    }

    func show() {
        guard panel == nil else { return }
        PreviewPanelController.shared.dismiss()

        let host = NSHostingView(rootView: CaptureBarView(defaultMode: lastMode) { [weak self] mode in
            if let mode { self?.pick(mode) } else { self?.close() }
        })
        let size = host.fittingSize
        let visible = (NSScreen.underMouse ?? NSScreen.screens[0]).visibleFrame
        let frame = CGRect(x: visible.midX - size.width / 2, y: visible.minY + 28, width: size.width, height: size.height)

        let panel = BarPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = NSWindow.Level.statusBar
        panel.isOpaque = false
        panel.backgroundColor = NSColor.clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.animationBehavior = NSWindow.AnimationBehavior.none
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [NSWindow.CollectionBehavior.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.contentView = host
        panel.onKey = { [weak self] event in self?.handle(event) ?? false }
        panel.onResignKey = { [weak self] in
            // Opening Shotput by link activates it, which takes the keyboard back for a moment.
            // Keep it unless another window really has it.
            DispatchQueue.main.async {
                guard self?.panel === panel, NSApp.keyWindow == nil else { return }
                panel.makeKey()
            }
        }
        // A click anywhere else puts the bar away, as a popover would.
        outsideClicks = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }
        self.panel = panel

        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        panel.alphaValue = 0
        panel.setFrame(reduceMotion ? frame : frame.offsetBy(dx: 0, dy: -10), display: false)
        panel.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.24
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.25, 1)
            panel.animator().alphaValue = 1
            panel.animator().setFrame(frame, display: true)
        }
    }

    /// Puts the bar away, then runs `next` once it is off screen, so it is never in a capture.
    func close(then next: (() -> Void)? = nil) {
        guard let panel else {
            next?()
            return
        }
        self.panel = nil
        panel.onResignKey = nil
        if let outsideClicks { NSEvent.removeMonitor(outsideClicks) }
        outsideClicks = nil
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.12
            panel.animator().alphaValue = 0
        }, completionHandler: {
            panel.orderOut(nil)
            next?()
        })
    }

    private func pick(_ mode: Mode) {
        lastMode = mode
        close { mode.perform() }
    }

    private func handle(_ event: NSEvent) -> Bool {
        switch event.keyCode {
        case 53:
            close()
        case 36, 76:
            pick(lastMode)
        default:
            guard let character = event.charactersIgnoringModifiers,
                  let mode = Mode.allCases.first(where: { $0.key == character }) else { return false }
            pick(mode)
        }
        return true
    }
}

final class BarPanel: NSPanel {
    var onKey: ((NSEvent) -> Bool)?
    var onResignKey: (() -> Void)?

    override var canBecomeKey: Bool { true }

    override func keyDown(with event: NSEvent) {
        if onKey?(event) != true { super.keyDown(with: event) }
    }

    override func cancelOperation(_ sender: Any?) {
        if let event = NSApp.currentEvent, onKey?(event) == true { return }
        super.cancelOperation(sender)
    }

    override func resignKey() {
        super.resignKey()
        onResignKey?()
    }
}

// MARK: The bar

/// `onPick(nil)` closes the bar.
struct CaptureBarView: View {
    let defaultMode: CaptureBar.Mode
    var onPick: (CaptureBar.Mode?) -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button { onPick(nil) } label: {
                Image(systemName: Icon.close.rawValue)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(QuietButtonStyle(shape: AnyShape(Circle())))
            .help("Close  esc")
            .padding(.horizontal, 8)

            separator
            group("Capture", [.area, .window, .screen])
            separator
            group("Record", [.recordArea, .recordScreen])
        }
        .padding(.vertical, 6)
        .padding(.leading, 2)
        .padding(.trailing, 6)
        .glassEffect(.regular, in: .rect(cornerRadius: 24, style: .continuous))
        .padding(16)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Capture bar")
    }

    private var separator: some View {
        Rectangle()
            .fill(.primary.opacity(0.1))
            .frame(width: 1, height: 40)
            .padding(.horizontal, 4)
    }

    private func group(_ title: String, _ modes: [CaptureBar.Mode]) -> some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)
                .fixedSize()
            HStack(spacing: 2) {
                ForEach(modes) { mode in
                    BarTile(mode: mode, isDefault: mode == defaultMode) { onPick(mode) }
                }
            }
        }
        .padding(.horizontal, 4)
    }
}

/// One mode: a symbol over a short name. The mode Return starts carries a faint fill.
private struct BarTile: View {
    let mode: CaptureBar.Mode
    let isDefault: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: mode.icon.rawValue)
                    .font(.system(size: 17))
                    .frame(width: 30, height: 22)
                    .overlay(alignment: .bottomTrailing) {
                        if mode.records {
                            Circle()
                                .fill(Color(nsColor: InkColor.red.nsColor))
                                .frame(width: 7, height: 7)
                                .offset(x: 1, y: 1)
                        }
                    }
                Text(mode.title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .fixedSize()
            }
            .frame(minWidth: 60)
            .padding(.horizontal, 4)
            .frame(height: 52)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.primary.opacity(isDefault ? 0.06 : 0)))
        }
        .buttonStyle(QuietButtonStyle(shape: AnyShape(RoundedRectangle(cornerRadius: 14, style: .continuous))))
        .help("\(mode.help)  \(mode.key)")
        .accessibilityLabel(mode.help)
    }
}

/// A bare control that shows a soft fill on hover and shrinks a touch when pressed.
private struct QuietButtonStyle: ButtonStyle {
    var shape: AnyShape
    @State private var hovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(shape)
            .background(shape.fill(.primary.opacity(configuration.isPressed ? 0.14 : hovered ? 0.08 : 0)))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
            .animation(.easeOut(duration: 0.12), value: hovered)
            .onHover { hovered = $0 }
    }
}
