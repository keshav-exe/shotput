import AppKit
import Combine
import ServiceManagement
import SwiftUI

/// The welcome guide shown on first launch. Words and choices on the left, a small scene on the
/// right that shows what the step is about.
@MainActor
final class OnboardingWindowController: NSWindowController, NSWindowDelegate {
    enum Step: Int, CaseIterable {
        /// `handoff` only shows when Shotput was made the screenshot tool and something else still
        /// holds the keys.
        case welcome, permission, defaultTool, handoff, shortcuts, mouse, ready
    }

    static let size = CGSize(width: 920, height: 600)

    private let state: OnboardingState

    init(start: Step) {
        state = OnboardingState(step: start)
        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: Self.size),
            styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false
        )
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.backgroundColor = Palette.background
        super.init(window: window)
        window.delegate = self
        state.onFinish = { [weak self] tryIt in
            self?.close()
            if tryIt {
                // Give the window a moment to leave, so it is not in the frozen still.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { HotAction.area.perform() }
            }
        }
        window.contentView = NSHostingView(rootView: OnboardingView(state: state))
        // The content runs under the transparent title bar, so the frame is the whole size.
        window.setFrame(CGRect(origin: .zero, size: Self.size), display: false)
        window.center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    var onClose: (() -> Void)?

    func show(_ step: Step? = nil) {
        if let step { state.step = step }
        if window?.isVisible == false { AppPresence.shared.windowDidOpen() }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        AppPresence.shared.windowDidClose()
        onClose?()
    }
}

@MainActor
final class OnboardingState: ObservableObject {
    typealias Step = OnboardingWindowController.Step

    @Published var step: Step
    /// The answer on the screenshot tool step. Yes is the recommendation, so it starts there.
    @Published var makesDefault = true
    /// Development only: treat Screen Recording as allowed, for renders of the guide.
    static var assumeScreenRecording = false
    var onFinish: ((_ tryIt: Bool) -> Void)?

    init(step: Step) { self.step = step }

    static func screenRecordingAllowed() -> Bool { assumeScreenRecording || CGPreflightScreenCaptureAccess() }

    /// The dots in the footer. The hand-off belongs to the screenshot tool step.
    static let dots: [Step] = Step.allCases.filter { $0 != .handoff }
    var dotIndex: Int { Self.dots.firstIndex(of: step == .handoff ? .defaultTool : step) ?? 0 }

    func advance() {
        switch step {
        case .defaultTool:
            applyDefaultChoice()
            step = makesDefault && HandoffStatus.current().needsAttention ? .handoff : .shortcuts
        case .handoff: step = .shortcuts
        case .ready: onFinish?(false)
        default: if let next = Step(rawValue: step.rawValue + 1) { step = next }
        }
    }

    func back() {
        switch step {
        case .shortcuts: step = makesDefault && HandoffStatus.current().needsAttention ? .handoff : .defaultTool
        case .welcome: break
        default: if let previous = Step(rawValue: step.rawValue - 1) { step = previous }
        }
    }

    private func applyDefaultChoice() {
        let settings = Settings.shared
        if makesDefault != settings.usesScreenshotKeys { settings.setUsesScreenshotKeys(makesDefault) }
    }
}

/// Who else answers ⇧⌘3, ⇧⌘4 and ⇧⌘5, checked live while the hand-off step is open.
struct HandoffStatus: Equatable {
    var macOSOwnsKeys: Bool
    var taken: [HotAction]
    var otherTools: [String]

    var needsAttention: Bool { macOSOwnsKeys || !taken.isEmpty || !otherTools.isEmpty }

    @MainActor
    static func current() -> HandoffStatus {
        let keys = Set(ScreenshotKeys.bindings.keys)
        return HandoffStatus(
            macOSOwnsKeys: SystemScreenshots.ownsScreenshotKeys,
            taken: HotKeyCenter.takenActions.filter { keys.contains($0) },
            otherTools: SystemScreenshots.otherTools.compactMap(\.localizedName)
        )
    }
}

struct OnboardingView: View {
    @ObservedObject var state: OnboardingState

    private static let paneWidth = OnboardingWindowController.size.width / 2

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                StepDots(count: OnboardingState.dots.count, current: state.dotIndex)
                    .padding(.bottom, 28)
                Group {
                    switch state.step {
                    case .welcome: WelcomeStep()
                    case .permission: PermissionStep()
                    case .defaultTool: DefaultToolStep(state: state)
                    case .handoff: HandoffStep()
                    case .shortcuts: ShortcutsStep()
                    case .mouse: MouseStep()
                    case .ready: ReadyStep()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .arrives()
                .id(state.step)

                footer
            }
            .padding(.horizontal, 44)
            .padding(.top, 58)
            .padding(.bottom, 32)
            .frame(width: Self.paneWidth)
            .background(Palette.background.color)

            StageView(state: state)
                .frame(width: Self.paneWidth)
                .frame(maxHeight: .infinity)
        }
        .frame(width: OnboardingWindowController.size.width, height: OnboardingWindowController.size.height)
        // Under the transparent title bar too, so the wallpaper reaches the top edge and the
        // window is exactly this size.
        .ignoresSafeArea()
    }

    private var footer: some View {
        HStack(spacing: 16) {
            if state.step != .welcome {
                Button { state.back() } label: {
                    Label { Text("Back") } icon: { Icon.back.view(size: 12, weight: .semibold) }
                        .padding(.vertical, 8)
                        .padding(.trailing, 8)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .controlSize(.large)
                .foregroundStyle(.secondary)
            }

            Spacer()

            if state.step == .ready {
                Button("Done") { state.onFinish?(false) }
                    .controlSize(.large)
            }
            Button { state.step == .ready ? state.onFinish?(true) : state.advance() } label: {
                HStack(spacing: 8) {
                    Text(nextTitle)
                    Icon.returnKey.view(size: 11, weight: .semibold).opacity(0.7)
                }
                .padding(.horizontal, 6)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
        }
    }

    private var nextTitle: String {
        switch state.step {
        case .welcome: "Get Started"
        case .ready: "Try a Capture"
        default: "Next"
        }
    }
}

private struct StepDots: View {
    let count: Int
    let current: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0 ..< count, id: \.self) { index in
                Capsule()
                    .fill(index == current ? Palette.ink.color : Palette.ink.color.opacity(0.18))
                    .frame(width: index == current ? 16 : 6, height: 6)
            }
        }
        .animation(.snappy(duration: 0.25), value: current)
        .accessibilityElement()
        .accessibilityLabel("Step \(current + 1) of \(count)")
    }
}

/// A page fades and rises in as it arrives, and the page it replaces goes at once. Nothing
/// animates out, so no half-gone page is ever left on screen or under the pointer.
private struct Arrival: ViewModifier {
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 8)
            .onAppear { withAnimation(.smooth(duration: 0.32)) { shown = true } }
    }
}

extension View {
    func arrives() -> some View { modifier(Arrival()) }
}

// MARK: Steps

private struct StepHeader: View {
    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 30, weight: .semibold))
                .tracking(-0.4)
                .fixedSize(horizontal: false, vertical: true)
            Text(message)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 28)
    }
}

private struct WelcomeStep: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 60, height: 60)
                .padding(.bottom, 18)
            StepHeader(
                title: "Welcome to Shotput",
                message: "Screenshots made for pasting. Press a key, drag an area, and it’s on your clipboard before you let go."
            )
            VStack(alignment: .leading, spacing: 14) {
                FeatureRow(.capture, "Capture", "an area, a window, or the whole screen.")
                FeatureRow(.annotate, "Annotate", "with arrows, boxes, steps and redaction.")
                FeatureRow(.pin, "Pin", "the ones you need again to the menu bar.")
                FeatureRow(.lock, "Keep", "every capture on your Mac. None of them leave it.")
            }
        }
    }
}

private struct FeatureRow: View {
    let icon: Icon
    let lead: String
    let rest: String

    init(_ icon: Icon, _ lead: String, _ rest: String) {
        self.icon = icon
        self.lead = lead
        self.rest = rest
    }

    var body: some View {
        HStack(spacing: 12) {
            icon.view(size: 13, weight: .medium)
                .foregroundStyle(Palette.accent.color)
                .frame(width: 28, height: 28)
                .background(Palette.accent.color.opacity(0.1), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            (Text(lead).fontWeight(.semibold) + Text(" ") + Text(rest).foregroundStyle(.secondary))
                .font(.system(size: 13))
        }
    }
}

private struct PermissionStep: View {
    /// Lets the dev harness render the granted state on a Mac where it has no permission.
    static func isGranted() -> Bool { OnboardingState.screenRecordingAllowed() }

    @State private var granted = PermissionStep.isGranted()
    @State private var asked = false
    private let poll = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            StepHeader(
                title: "Allow Screen Recording",
                message: "macOS only lets Shotput see your screen once you allow it, and Shotput only looks while you take a screenshot."
            )

            SettingCard(icon: .screen, title: "Screen Recording", detail: "Needed to take screenshots.") {
                if granted {
                    StatusPill(text: "Allowed", good: true)
                        .arrives()
                } else {
                    Button(asked ? "Open Again" : "Allow…") {
                        UserDefaults.standard.set(true, forKey: "askedForScreenRecording")
                        UserDefaults.standard.set(OnboardingWindowController.Step.permission.rawValue, forKey: "onboardingResumeStep")
                        if asked || !CGRequestScreenCaptureAccess() { ScreenPermission.openSettings() }
                        asked = true
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

            if !granted && asked {
                VStack(alignment: .leading, spacing: 10) {
                    NumberedRow(1, "Turn on Shotput under Screen & System Audio Recording.")
                    NumberedRow(2, "macOS asks to quit and reopen Shotput. Let it, and this guide picks up here.")
                    Button("Reopen Shotput") { Relaunch.now() }
                        .padding(.leading, 34)
                }
                .font(.system(size: 13))
                .padding(.top, 20)
                .arrives()
            }
        }
        .onReceive(poll) { _ in
            let now = PermissionStep.isGranted()
            if now != granted { granted = now }
        }
    }
}

private struct DefaultToolStep: View {
    @ObservedObject var state: OnboardingState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            StepHeader(
                title: "Make Shotput your screenshot tool?",
                message: "Then ⇧⌘3, ⇧⌘4 and ⇧⌘5 open Shotput instead of the tool you use now. You can change this later in Settings."
            )
            VStack(spacing: 10) {
                ChoiceCard(
                    selected: state.makesDefault,
                    title: "Yes, use Shotput",
                    detail: "⇧⌘4 for an area, ⇧⌘3 for the screen, ⇧⌘5 to annotate.",
                    tag: "Recommended"
                ) { state.makesDefault = true }
                ChoiceCard(
                    selected: !state.makesDefault,
                    title: "No, keep my current tool",
                    detail: "Shotput stays on ⌃⌥⌘A and its own keys, and leaves yours alone."
                ) { state.makesDefault = false }
            }
        }
    }
}

private struct ChoiceCard: View {
    let selected: Bool
    let title: String
    let detail: String
    var tag: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle().strokeBorder(selected ? Palette.accent.color : Palette.ink.color.opacity(0.25), lineWidth: 1.5)
                    if selected { Circle().fill(Palette.accent.color).padding(4) }
                }
                .frame(width: 18, height: 18)
                .padding(.top, 1)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(title).font(.system(size: 14, weight: .semibold))
                        if let tag {
                            Text(tag)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Palette.accent.color)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(Palette.accent.color.opacity(0.12), in: Capsule())
                        }
                    }
                    Text(detail)
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.surface.color, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(selected ? Palette.accent.color : Palette.hairline.color, lineWidth: selected ? 1.5 : 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(PressableCard())
        .accessibilityAddTraits(selected ? .isSelected : [])
        .animation(.snappy(duration: 0.2), value: selected)
    }
}

/// Settles a little under the finger, so the card feels pressed rather than merely clicked.
private struct PressableCard: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Turning off what still answers the screenshot keys. macOS hears them before any app does,
/// and the sandbox can't change that for you, so this shows exactly where to click.
private struct HandoffStep: View {
    @State private var status = HandoffStatus.current()
    private let poll = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            StepHeader(
                title: "Hand over the keys",
                message: "macOS answers ⇧⌘3, ⇧⌘4 and ⇧⌘5 before any app hears them. Turn its shortcuts off and they’re Shotput’s."
            )

            SettingCard(icon: .keyboard, title: "macOS screenshot shortcuts", detail: status.macOSOwnsKeys
                ? "Keyboard Shortcuts → Screenshots. Untick ⇧⌘3, ⇧⌘4 and ⇧⌘5. Leave the clipboard ones on."
                : "Turned off. The keys reach Shotput now.") {
                if status.macOSOwnsKeys {
                    Button("Open…") { SystemScreenshots.openKeyboardShortcuts() }
                        .buttonStyle(.borderedProminent)
                } else {
                    StatusPill(text: "Off", good: true)
                        .arrives()
                }
            }

            ForEach(status.otherTools, id: \.self) { name in
                SettingCard(icon: .warning, title: "\(name) is open", detail: "It may hold the same keys. Quit it, or clear them in its settings.") {
                    Button("Quit") { SystemScreenshots.otherTools.first { $0.localizedName == name }?.terminate() }
                }
                .padding(.top, 10)
            }

            if !status.taken.isEmpty, !status.macOSOwnsKeys, status.otherTools.isEmpty {
                Text("Another app still holds \(status.taken.compactMap { Settings.shared.shortcuts[$0]?.display }.joined(separator: ", ")).")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.top, 14)
            }
        }
        .onReceive(poll) { _ in
            // Registering again is how Shotput finds out the keys came free.
            HotKeyCenter.reload()
            let now = HandoffStatus.current()
            if now != status { status = now }
        }
    }
}

private struct ShortcutsStep: View {
    @ObservedObject private var settings = Settings.shared
    private let shown: [HotAction] = [.area, .areaAnnotate, .window, .screen, .text]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            StepHeader(
                title: "Your shortcuts",
                message: "They work from any app. Pressing one again while you select backs out."
            )
            VStack(spacing: 0) {
                ForEach(shown) { action in
                    HStack {
                        Text(action.title).font(.system(size: 13, weight: .medium))
                        Spacer()
                        KeyCaps(shortcut: settings.shortcuts[action] ?? .none, size: .small)
                    }
                    .frame(height: 40)
                    if action != shown.last { Divider() }
                }
            }
            .padding(.horizontal, 14)
            .card()
        }
    }
}

private struct MouseStep: View {
    private static let logiBundleIDs = ["com.logi.optionsplus", "com.logitech.logioptionsplus"]
    private static let download = URL(string: "https://www.logitech.com/software/logi-options-plus.html")!

    private var logiApp: URL? {
        Self.logiBundleIDs.lazy.compactMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            StepHeader(
                title: "Capture from a mouse button",
                message: "Logi Options+ can press Shotput’s keys for you. The gesture button fits five of them."
            )
            VStack(alignment: .leading, spacing: 12) {
                NumberedRow(1, "Open Logi Options+ and pick your mouse.")
                NumberedRow(2, "Click the gesture or thumb button on the picture.")
                NumberedRow(3, "Choose Keyboard shortcut, then press the Shotput keys.")
            }
            .font(.system(size: 13))
            Group {
                if let logiApp {
                    Button("Open Logi Options+") { NSWorkspace.shared.open(logiApp) }
                } else {
                    Button("Get Logi Options+") { NSWorkspace.shared.open(Self.download) }
                }
            }
            .padding(.top, 20)
        }
    }
}

private struct ReadyStep: View {
    @ObservedObject private var updates = Updates.shared
    @State private var opensAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            StepHeader(
                title: "Almost ready",
                message: "Choose how Shotput runs. It lives in the menu bar: click the icon for pins, right-click for everything else."
            )
            VStack(spacing: 10) {
                SettingCard(icon: .power, title: "Open at login", detail: "Shotput is there whenever your Mac starts.") {
                    Toggle("", isOn: $opensAtLogin).labelsHidden().toggleStyle(.switch)
                }
                SettingCard(icon: .update, title: "Install updates automatically", detail: "Downloads in the background, installs when Shotput quits.") {
                    Toggle("", isOn: Binding(get: { updates.isAutomatic }, set: { updates.isAutomatic = $0 }))
                        .labelsHidden().toggleStyle(.switch)
                }
            }
            .onChange(of: opensAtLogin) { _, enabled in
                do {
                    if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                } catch {
                    opensAtLogin = SMAppService.mainApp.status == .enabled
                }
            }
        }
    }
}

// MARK: Pieces

/// One setting as a raised row: a symbol, what it is, and its control.
private struct SettingCard<Control: View>: View {
    let icon: Icon
    let title: String
    let detail: String
    @ViewBuilder let control: Control

    var body: some View {
        HStack(spacing: 14) {
            icon.view(size: 15, weight: .medium)
                .foregroundStyle(Palette.ink.color.opacity(0.75))
                .frame(width: 36, height: 36)
                .background(Palette.surfaceMuted.color, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 13.5, weight: .semibold))
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            control
        }
        .padding(14)
        .card()
    }
}

private struct StatusPill: View {
    let text: String
    let good: Bool

    var body: some View {
        HStack(spacing: 5) {
            Icon.checkmark.view(size: 10, weight: .bold)
            Text(text)
        }
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(good ? Color.green : Color.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background((good ? Color.green : Color.secondary).opacity(0.12), in: Capsule())
    }
}

private extension View {
    /// The guide's one surface: a raised panel with a hairline edge.
    func card() -> some View {
        background(Palette.surface.color, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Palette.hairline.color))
    }
}

private struct NumberedRow: View {
    let number: Int
    let text: String

    init(_ number: Int, _ text: String) {
        self.number = number
        self.text = text
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("\(number)")
                .font(.callout.weight(.semibold).monospacedDigit())
                .foregroundStyle(Palette.accent.color)
                .frame(width: 22, height: 22)
                .background(Palette.accent.color.opacity(0.12), in: Circle())
                .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 5 }
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// A shortcut drawn as the physical keys, one cap each. Shotput's one recurring motif: the
/// guide teaches keys, so it shows keys.
struct KeyCaps: View {
    enum Size { case small, regular }

    let shortcut: Shortcut
    var size: Size = .regular
    /// Keys up to and including this index are drawn held down. The welcome film drives it.
    var pressed: Int?

    private var keys: [String] {
        guard shortcut.isSet else { return [] }
        let flags = shortcut.flags
        var keys: [String] = []
        if flags.contains(.control) { keys.append("⌃") }
        if flags.contains(.option) { keys.append("⌥") }
        if flags.contains(.shift) { keys.append("⇧") }
        if flags.contains(.command) { keys.append("⌘") }
        return keys + [shortcut.keyName]
    }

    private var metrics: (font: Font, side: CGFloat, radius: CGFloat, edge: CGFloat, gap: CGFloat) {
        switch size {
        case .small: (.system(size: 11, weight: .medium), 20, 5, 1.5, 3)
        case .regular: (.system(size: 13, weight: .medium), 26, 6, 2, 4)
        }
    }

    var body: some View {
        if keys.isEmpty {
            Text("Not set").font(.callout).foregroundStyle(.tertiary)
        } else {
            let m = metrics
            HStack(spacing: m.gap) {
                ForEach(Array(keys.enumerated()), id: \.offset) { index, key in
                    let isDown = pressed.map { index <= $0 } ?? false
                    Text(key)
                        .font(m.font)
                        .foregroundStyle(Palette.ink.color)
                        .padding(.horizontal, key.count > 1 ? m.side * 0.3 : 0)
                        .frame(minWidth: m.side, minHeight: m.side)
                        .background(
                            RoundedRectangle(cornerRadius: m.radius, style: .continuous)
                                .fill(Palette.surface.color)
                                .overlay(RoundedRectangle(cornerRadius: m.radius, style: .continuous)
                                    .strokeBorder(Palette.ink.color.opacity(0.14), lineWidth: 1))
                        )
                        // The cap sits on a darker base; pressing it closes the gap.
                        .offset(y: isDown ? m.edge * 0.75 : 0)
                        .background(
                            RoundedRectangle(cornerRadius: m.radius, style: .continuous)
                                .fill(Palette.ink.color.opacity(0.16))
                                .offset(y: m.edge)
                        )
                        .padding(.bottom, m.edge)
                }
            }
            .accessibilityElement()
            .accessibilityLabel(shortcut.display)
        }
    }
}

enum Relaunch {
    /// Starts a fresh copy of Shotput and quits this one, so a new Screen Recording grant applies.
    @MainActor
    static func now() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }
}
