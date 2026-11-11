import AppKit
import Combine
import ServiceManagement
import SwiftUI

/// The welcome guide shown on first launch: permission, shortcuts, and setting up a mouse button.
@MainActor
final class OnboardingWindowController: NSWindowController, NSWindowDelegate {
    enum Step: Int, CaseIterable {
        case welcome, permission, shortcuts, mouse, ready
    }

    private let state: OnboardingState

    init(start: Step) {
        state = OnboardingState(step: start)
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 600, height: 600),
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
    @Published var step: OnboardingWindowController.Step
    var onFinish: ((_ tryIt: Bool) -> Void)?

    init(step: OnboardingWindowController.Step) { self.step = step }

    func advance() {
        if let next = OnboardingWindowController.Step(rawValue: step.rawValue + 1) { step = next } else { onFinish?(false) }
    }

    func back() {
        if let previous = OnboardingWindowController.Step(rawValue: step.rawValue - 1) { step = previous }
    }
}

struct OnboardingView: View {
    @ObservedObject var state: OnboardingState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch state.step {
                case .welcome: WelcomeStep()
                case .permission: PermissionStep()
                case .shortcuts: ShortcutsStep()
                case .mouse: MouseStep()
                case .ready: ReadyStep()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.horizontal, 48)
            .padding(.top, 40)
            .padding(.bottom, 24)
            .id(state.step)
            .transition(reduceMotion ? .opacity : .asymmetric(
                insertion: .opacity.combined(with: .offset(x: 24)),
                removal: .opacity.combined(with: .offset(x: -24))
            ))

            footer
        }
        .frame(width: 600, height: 600)
        .animation(.snappy(duration: 0.28), value: state.step)
    }

    private var footer: some View {
        HStack {
            Text("\(state.step.rawValue + 1) of \(OnboardingWindowController.Step.allCases.count)")
                .font(.callout.monospacedDigit())
                .foregroundStyle(.tertiary)
                .contentTransition(.numericText())

            Spacer()

            if state.step != .welcome {
                Button("Back") { state.back() }
                    .controlSize(.large)
            }
            if state.step == .ready {
                Button("Done") { state.onFinish?(false) }
                    .controlSize(.large)
                Button("Try a Capture") { state.onFinish?(true) }
                    .controlSize(.large)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            } else {
                Button(state.step == .welcome ? "Get Started" : "Continue") { state.advance() }
                    .controlSize(.large)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 48)
        .padding(.vertical, 20)
        .overlay(alignment: .top) { Rectangle().fill(Palette.hairline.color).frame(height: 1) }
    }
}

// MARK: Steps

private struct StepHeader: View {
    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.spacingS) {
            Text(title)
                .font(.title.weight(.semibold))
            Text(message)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Opens on the one thing worth learning first: the shortcut, drawn as the keys you press.
private struct WelcomeStep: View {
    @ObservedObject private var settings = Settings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Shotput").font(.title2.weight(.semibold))
                    Text("Screenshots for pasting, from the menu bar.").foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 40)

            Text("Press")
                .font(.title3)
                .foregroundStyle(.secondary)
                .padding(.bottom, 14)
            KeyCaps(shortcut: settings.shortcuts[.area] ?? .none, size: .large)
            Text("in any app, drag over what you want, then paste. It is on the clipboard the moment you let go.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 18)

            Spacer(minLength: 40)

            Text("Sandboxed with no network access, so nothing you capture leaves this Mac.")
                .font(.callout)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct PermissionStep: View {
    @State private var granted = CGPreflightScreenCaptureAccess()
    @State private var asked = false
    private let poll = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.spacingL) {
            StepHeader(
                title: "Allow Screen Recording",
                message: "macOS only lets Shotput see your screen while you take a screenshot, and only once you allow it."
            )

            if granted {
                Label { Text("Screen Recording is on") } icon: { Icon.check.view(size: 15) }
                    .font(.headline)
                    .foregroundStyle(.green)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    NumberedRow(1, "Click Open System Settings below.")
                    NumberedRow(2, "Turn on Shotput under Screen & System Audio Recording.")
                    NumberedRow(3, "macOS asks to quit and reopen Shotput. Let it, and this guide picks up where you left off.")
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: Metrics.spacingS) {
                    Button("Open System Settings") {
                        UserDefaults.standard.set(true, forKey: "askedForScreenRecording")
                        UserDefaults.standard.set(OnboardingWindowController.Step.permission.rawValue, forKey: "onboardingResumeStep")
                        if asked || !CGRequestScreenCaptureAccess() { ScreenPermission.openSettings() }
                        asked = true
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    if asked {
                        Button("Reopen Shotput") { Relaunch.now() }
                            .controlSize(.large)
                    }
                }
            }
        }
        .onReceive(poll) { _ in
            let now = CGPreflightScreenCaptureAccess()
            if now != granted { granted = now }
        }
    }
}

private struct ShortcutsStep: View {
    @ObservedObject private var settings = Settings.shared
    private let shown: [HotAction] = [.area, .areaAnnotate, .window, .screen, .text, .annotateLast]

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.spacingL) {
            StepHeader(
                title: "Your shortcuts",
                message: "They work from any app. Change them whenever you like in Settings."
            )
            VStack(spacing: 0) {
                ForEach(shown) { action in
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(action.title).font(.body.weight(.medium))
                            Text(action.detail).font(.callout).foregroundStyle(.secondary)
                        }
                        Spacer()
                        KeyCaps(shortcut: settings.shortcuts[action] ?? .none)
                    }
                    .padding(.vertical, 8)
                    if action != shown.last { Divider() }
                }
            }
            .padding(.horizontal, Metrics.spacingM)
            .padding(.vertical, Metrics.spacingXS)
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
        VStack(alignment: .leading, spacing: Metrics.spacingL) {
            StepHeader(
                title: "Capture from a mouse button",
                message: "Logi Options+ can press Shotput's keys for you. Press the same button again while selecting to back out."
            )
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    NumberedRow(1, "Open Logi Options+ and pick your mouse.")
                    Spacer()
                    if let logiApp {
                        Button("Open") { NSWorkspace.shared.open(logiApp) }
                    } else {
                        Button("Get It") { NSWorkspace.shared.open(Self.download) }
                    }
                }
                NumberedRow(2, "Click the gesture or thumb button on the picture.")
                NumberedRow(3, "Choose Keyboard shortcut, then press the Shotput keys.")
            }

            GestureMap()
        }
    }
}

/// The gesture button's five directions, each with the Shotput action that suits it.
private struct GestureMap: View {
    @ObservedObject private var settings = Settings.shared

    var body: some View {
        Grid(horizontalSpacing: 6, verticalSpacing: 6) {
            GridRow {
                Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                cell("Up", "Annotate", .areaAnnotate)
                Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
            }
            GridRow {
                cell("Left", "Window", .window)
                cell("Click", "Area", .area, emphasised: true)
                cell("Right", "Last capture", .annotateLast)
            }
            GridRow {
                Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                cell("Down", "Screen", .screen)
                Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Suggested gesture button layout")
    }

    private func cell(_ gesture: String, _ name: String, _ action: HotAction, emphasised: Bool = false) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                Text(gesture).foregroundStyle(.secondary)
                Text(name).fontWeight(.medium)
            }
            .font(.callout)
            .lineLimit(1)
            KeyCaps(shortcut: settings.shortcuts[action] ?? .none, size: .small)
        }
        .frame(width: 150, height: 64)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(emphasised ? Palette.accent.color.opacity(0.1) : Palette.surfaceMuted.color.opacity(0.6))
        )
    }
}

private struct ReadyStep: View {
    @ObservedObject private var settings = Settings.shared
    @State private var opensAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.spacingL) {
            StepHeader(
                title: "You're set",
                message: "Shotput is in the menu bar. Click its icon any time for captures and Settings."
            )
            VStack(spacing: 0) {
                row("Open Shotput at login") {
                    Toggle("", isOn: $opensAtLogin).labelsHidden().toggleStyle(.switch)
                }
                Divider()
                row("After a capture") {
                    Picker("", selection: $settings.afterCapture) {
                        ForEach(Settings.AfterCapture.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                Divider()
                row("Play a sound on capture") {
                    Toggle("", isOn: $settings.playsSound).labelsHidden().toggleStyle(.switch)
                }
            }
            .padding(.horizontal, Metrics.spacingM)
            .card()
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

private extension ReadyStep {
    func row(_ title: String, @ViewBuilder control: () -> some View) -> some View {
        HStack {
            Text(title)
            Spacer()
            control()
        }
        .frame(minHeight: 44)
    }
}

private extension View {
    /// The guide's one surface: a raised panel with a hairline edge.
    func card() -> some View {
        background(Palette.surface.color, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Palette.hairline.color))
    }
}

// MARK: Pieces

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
    enum Size { case small, regular, large }

    let shortcut: Shortcut
    var size: Size = .regular
    @State private var pressed: Int?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
        case .large: (.system(size: 26, weight: .regular), 58, 12, 4, 10)
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
            .task {
                guard size == .large, !reduceMotion else { return }
                // Press the keys down in order, hold, release: the shortcut being typed once.
                try? await Task.sleep(for: .milliseconds(500))
                for index in keys.indices {
                    withAnimation(.snappy(duration: 0.12)) { pressed = index }
                    try? await Task.sleep(for: .milliseconds(90))
                }
                try? await Task.sleep(for: .milliseconds(260))
                withAnimation(.spring(duration: 0.3, bounce: 0.35)) { pressed = nil }
            }
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
