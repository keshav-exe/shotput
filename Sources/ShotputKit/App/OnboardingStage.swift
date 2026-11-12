import AppKit
import Combine
import SwiftUI

/// The right half of the welcome guide: a dark stage with one small scene per step, showing the
/// thing the step talks about rather than describing it again.
struct StageView: View {
    @ObservedObject var state: OnboardingState
    @ObservedObject private var wallpaper = GuideWallpaper.shared

    var body: some View {
        ZStack {
            Color(nsColor: NSColor(hex: 0x1C1C1A))
            if let image = wallpaper.image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: OnboardingWindowController.size.width / 2, height: OnboardingWindowController.size.height)
                    .clipped()
                    .arrives()
            }
            // A light veil, so a bright wallpaper doesn't outshine the scene.
            Color.black.opacity(0.18)
            scene
                .arrives()
                .id(sceneID)
        }
        // Fixed before clipping, so a scene wider than the pane, like the keyboard, is cut at
        // the pane's edge instead of spilling over the words.
        .frame(width: OnboardingWindowController.size.width / 2, height: OnboardingWindowController.size.height)
        .environment(\.colorScheme, .dark)
        .clipped()
        .onAppear { wallpaper.load() }
        .onChange(of: state.step) { _, _ in wallpaper.load() }
    }

    /// Steps that share a scene keep it, so it doesn't fade out and back in.
    private var sceneID: String {
        switch state.step {
        case .defaultTool: "keys-\(state.makesDefault)"
        default: "\(state.step)"
        }
    }

    @ViewBuilder private var scene: some View {
        switch state.step {
        case .welcome:
            WelcomeFilm()
                .scaleEffect(0.84)
                .frame(width: WelcomeFilm.stage.width * 0.84, height: WelcomeFilm.stage.height * 0.84)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .shadow(color: .black.opacity(0.5), radius: 24, y: 10)
        case .permission: PermissionScene(granted: state.screenRecordingAllowed)
        case .defaultTool:
            state.makesDefault
                ? KeyboardScene(lit: ["⇧", "⌘", "3", "4", "5"], cycle: ["3", "4", "5"])
                : KeyboardScene(lit: ["⌃", "⌥", "⌘", "A"], cycle: ["A"])
        case .handoff: HandoffScene(macOSOwns: state.handoff.macOSOwnsKeys)
        case .shortcuts: ShortcutKeyboardScene()
        case .mouse: GestureMap().padding(14).stagePanel(radius: 24)
        case .ready: ReadyScene()
        }
    }
}

// MARK: Permission

/// A Privacy & Security list where Shotput's switch is the one that matters, and flips when the
/// real permission does.
private struct PermissionScene: View {
    let granted: Bool
    @State private var pulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Screen & System Audio Recording")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.45))
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
            row(on: true) { Placeholder(width: 120) }
            Divider().overlay(.white.opacity(0.06))
            row(on: true) { Placeholder(width: 90) }
            Divider().overlay(.white.opacity(0.06))
            row(on: granted, highlighted: true) {
                HStack(spacing: 10) {
                    Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 30, height: 30)
                    Text("Shotput").font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                }
            }
        }
        .frame(width: 340)
        .stagePanel(radius: 18)
        .animation(.spring(duration: 0.4, bounce: 0.3), value: granted)
        .onAppear { if !reduceMotion { pulse = true } }
    }

    private func row(on: Bool, highlighted: Bool = false, @ViewBuilder _ content: () -> some View) -> some View {
        HStack {
            if !highlighted {
                RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.white.opacity(0.09)).frame(width: 30, height: 30)
            }
            content()
            Spacer()
            FauxSwitch(on: on)
                .background {
                    if highlighted && !on {
                        Capsule()
                            .strokeBorder(Palette.accent.color, lineWidth: 2)
                            .padding(-5)
                            .opacity(pulse ? 0 : 0.8)
                            .scaleEffect(pulse ? 1.25 : 1)
                            .animation(.easeOut(duration: 1.4).repeatForever(autoreverses: false), value: pulse)
                    }
                }
        }
        .padding(.horizontal, 18)
        .frame(height: 58)
    }
}

private struct Placeholder: View {
    let width: CGFloat
    var body: some View { Capsule().fill(.white.opacity(0.09)).frame(width: width, height: 12) }
}

private struct FauxSwitch: View {
    let on: Bool

    var body: some View {
        Capsule()
            .fill(on ? Palette.accent.color : Color.white.opacity(0.14))
            .frame(width: 40, height: 24)
            .overlay(alignment: on ? .trailing : .leading) {
                Circle().fill(.white).padding(2).shadow(color: .black.opacity(0.25), radius: 1, y: 1)
            }
            .animation(.spring(duration: 0.3, bounce: 0.25), value: on)
    }
}

// MARK: Keyboard

/// The left of a Mac keyboard, with the keys of a shortcut lit and its last key tapped in turn.
struct KeyboardScene: View {
    let lit: Set<String>
    /// Keys pressed one after another while the modifiers stay lit.
    let cycle: [String]

    @State private var pressed = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let beat = Timer.publish(every: 0.9, on: .main, in: .common).autoconnect()

    private static let unit: CGFloat = 46
    private static let gap: CGFloat = 6
    private static let rows: [[(String, CGFloat)]] = [
        [("esc", 1.5), ("F1", 1), ("F2", 1), ("F3", 1), ("F4", 1), ("F5", 1), ("F6", 1)],
        [("§", 1), ("1", 1), ("2", 1), ("3", 1), ("4", 1), ("5", 1), ("6", 1), ("7", 1)],
        [("⇥", 1.5), ("Q", 1), ("W", 1), ("E", 1), ("R", 1), ("T", 1), ("Y", 1)],
        [("⇪", 1.8), ("A", 1), ("S", 1), ("D", 1), ("F", 1), ("G", 1), ("H", 1)],
        [("⇧", 2.3), ("Z", 1), ("X", 1), ("C", 1), ("V", 1), ("B", 1), ("N", 1)],
        [("fn", 1), ("⌃", 1), ("⌥", 1), ("⌘", 1.4), ("", 5)],
    ]

    private static let names: [String: String] = ["⌃": "control", "⌥": "option", "⌘": "command", "⇧": "shift"]

    var body: some View {
        VStack(alignment: .leading, spacing: Self.gap) {
            ForEach(Array(Self.rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: Self.gap) {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, key in cap(key.0, width: key.1) }
                }
            }
        }
        .padding(18)
        .stagePanel(radius: 22)
        .fixedSize()
        // Wider than the pane on purpose: it starts 40 points in and runs off the right edge,
        // so it's laid over the pane instead of widening it.
        .padding(.leading, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .frame(width: OnboardingWindowController.size.width / 2, alignment: .leading)
        .onReceive(beat) { _ in
            guard !reduceMotion, cycle.count > 0 else { return }
            withAnimation(.spring(duration: 0.25, bounce: 0.4)) { pressed = (pressed + 1) % (cycle.count * 2) }
        }
        .accessibilityElement()
        .accessibilityLabel("Keyboard with \(lit.sorted().joined(separator: " ")) highlighted")
    }

    /// Every other beat a key is down, so each press reads as its own tap.
    private var downKey: String? {
        guard !reduceMotion, pressed % 2 == 0 else { return nil }
        return cycle[pressed / 2]
    }

    private func cap(_ label: String, width: CGFloat) -> some View {
        let isLit = lit.contains(label)
        let isDown = downKey == label || (isLit && !cycle.contains(label) && downKey != nil)
        return ZStack(alignment: Self.names[label] == nil ? .center : .bottomLeading) {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(isLit ? Color.white.opacity(isDown ? 0.26 : 0.17) : Color.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(isLit ? Color.white.opacity(0.4) : Color.white.opacity(0.05))
                )
                .shadow(color: isDown ? Palette.accent.color.opacity(0.55) : .clear, radius: 12)
            if let name = Self.names[label] {
                VStack(alignment: .leading, spacing: 2) {
                    Text(label).font(.system(size: 15, weight: .medium))
                    Text(name).font(.system(size: 9, weight: .medium)).lineLimit(1).minimumScaleFactor(0.8)
                }
                .padding(6)
                .foregroundStyle(isLit ? .white : .white.opacity(0.3))
            } else {
                Text(label)
                    .font(.system(size: label.count > 1 ? 11 : 17, weight: .medium))
                    .foregroundStyle(isLit ? .white : .white.opacity(0.3))
            }
        }
        .frame(width: Self.unit * width + Self.gap * (width - 1).rounded(.down), height: Self.unit)
        .scaleEffect(isDown ? 0.94 : 1)
    }
}

/// The keyboard lit with whatever Capture area is set to right now.
private struct ShortcutKeyboardScene: View {
    @ObservedObject private var settings = Settings.shared

    var body: some View {
        let shortcut = settings.shortcuts[.area] ?? HotAction.area.defaultShortcut
        var keys: Set<String> = []
        if shortcut.flags.contains(.control) { keys.insert("⌃") }
        if shortcut.flags.contains(.option) { keys.insert("⌥") }
        if shortcut.flags.contains(.shift) { keys.insert("⇧") }
        if shortcut.flags.contains(.command) { keys.insert("⌘") }
        let key = shortcut.keyName
        return KeyboardScene(lit: keys.union([key]), cycle: [key])
    }
}

// MARK: Hand-off

/// The list in Keyboard Shortcuts → Screenshots, ticked while macOS still owns the keys.
private struct HandoffScene: View {
    let macOSOwns: Bool

    /// The last value says whether Shotput takes the keys. The clipboard ones stay with macOS.
    private let rows: [(String, String, Bool)] = [
        ("Save picture of screen as a file", "⇧⌘3", true),
        ("Copy picture of screen to the clipboard", "⌃⇧⌘3", false),
        ("Save picture of selected area as a file", "⇧⌘4", true),
        ("Copy picture of selected area to the clipboard", "⌃⇧⌘4", false),
        ("Screenshot and recording options", "⇧⌘5", true),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Icon.keyboard.view(size: 12, weight: .semibold)
                Text("Keyboard Shortcuts  ›  Screenshots")
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white.opacity(0.45))
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                let ticked = row.2 ? macOSOwns : true
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(ticked ? Palette.accent.color : Color.white.opacity(0.08))
                        .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(.white.opacity(ticked ? 0 : 0.2)))
                        .overlay { if ticked { Icon.checkmark.view(size: 10, weight: .bold).foregroundStyle(.white) } }
                        .frame(width: 18, height: 18)
                        .animation(.spring(duration: 0.3).delay(Double(index) * 0.06), value: macOSOwns)
                    Text(row.0).font(.system(size: 12.5)).foregroundStyle(.white.opacity(row.2 ? 0.9 : 0.5)).lineLimit(1)
                    Spacer(minLength: 8)
                    Text(row.1).font(.system(size: 12.5, weight: .medium)).foregroundStyle(.white.opacity(0.5))
                }
                .padding(.horizontal, 16)
                .frame(height: 42)
                .background(index % 2 == 1 ? Color.white.opacity(0.025) : .clear)
            }
        }
        .frame(width: 388)
        .stagePanel(radius: 16)
    }
}

// MARK: Mouse

/// The gesture button's five directions, each with the Shotput action that suits it.
private struct GestureMap: View {
    @ObservedObject private var settings = Settings.shared

    var body: some View {
        Grid(horizontalSpacing: 8, verticalSpacing: 8) {
            GridRow {
                Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                cell("Up", "Annotate", .areaAnnotate)
                Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
            }
            GridRow {
                cell("Left", "Window", .window)
                cell("Click", "Area", .area, emphasised: true)
                cell("Right", "Last", .annotateLast)
            }
            GridRow {
                Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                cell("Down", "Screen", .screen)
                Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Suggested gesture button layout")
    }

    private func cell(_ gesture: String, _ name: String, _ action: HotAction, emphasised: Bool = false) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 4) {
                Text(gesture).foregroundStyle(.white.opacity(0.45))
                Text(name).fontWeight(.semibold).foregroundStyle(.white)
            }
            .font(.system(size: 12))
            .lineLimit(1)
            KeyCaps(shortcut: settings.shortcuts[action] ?? .none, size: .small)
        }
        .frame(width: 128, height: 76)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(emphasised ? Palette.accent.color.opacity(0.22) : Color.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(emphasised ? Palette.accent.color.opacity(0.6) : Color.white.opacity(0.06))
        )
    }
}

// MARK: Ready

/// The menu bar with Shotput's icon and its tray of pins dropped open beneath it.
private struct ReadyScene: View {
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                Spacer()
                Icon.capture.view(size: 13, weight: .semibold)
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 22)
                    .background(.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                Capsule().fill(.white.opacity(0.18)).frame(width: 18, height: 10)
                Capsule().fill(.white.opacity(0.18)).frame(width: 40, height: 10)
            }
            .padding(.horizontal, 18)
            .frame(height: 30)
            .background(.ultraThinMaterial)

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Pinned").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                    Text("3 of 15").font(.system(size: 12).monospacedDigit()).foregroundStyle(.white.opacity(0.45))
                    Spacer()
                }
                HStack(spacing: 8) {
                    ForEach(0 ..< 3) { index in
                        FauxCapture(seed: index)
                            .offset(y: shown ? 0 : 14)
                            .opacity(shown ? 1 : 0)
                            .animation(.spring(duration: 0.5, bounce: 0.3).delay(0.15 + Double(index) * 0.08), value: shown)
                    }
                }
            }
            .padding(16)
            .stagePanel(radius: 16)
            .padding(.top, 10)
            .padding(.leading, 70)
            .padding(.trailing, 16)

            Spacer()
        }
        .onAppear { shown = true }
        .transaction { if reduceMotion { $0.animation = nil } }
    }
}

/// A capture thumbnail drawn from a few bars: a window, some text, a picture.
private struct FauxCapture: View {
    let seed: Int
    private let tints: [UInt] = [0x5AA0FF, 0xF2A65A, 0x7CC68D]

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 3) {
                ForEach(0 ..< 3) { _ in Circle().fill(.white.opacity(0.25)).frame(width: 4, height: 4) }
            }
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color(nsColor: NSColor(hex: tints[seed % tints.count])).opacity(0.75))
                .frame(height: 34)
            Capsule().fill(.white.opacity(0.2)).frame(width: 60, height: 5)
            Capsule().fill(.white.opacity(0.12)).frame(width: 40, height: 5)
        }
        .padding(8)
        .frame(width: 104, height: 86, alignment: .topLeading)
        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

// MARK: Backdrop

private extension View {
    /// A dark frosted panel, so a scene reads on any wallpaper.
    func stagePanel(radius: CGFloat) -> some View {
        background(.regularMaterial, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(.white.opacity(0.12)))
            .shadow(color: .black.opacity(0.35), radius: 24, y: 12)
    }
}

/// The wallpaper behind the guide's scenes: your own, captured the way window backdrops are once
/// Screen Recording is allowed, before that the desktop picture file if it can be read, and
/// otherwise a picture that ships with macOS.
@MainActor
final class GuideWallpaper: ObservableObject {
    static let shared = GuideWallpaper()

    @Published private(set) var image: CGImage?
    private var isCaptured = false
    private var isLoading = false

    private static let fallbacks = [
        "/System/Library/Desktop Pictures/.wallpapers/Sonoma Horizon/Sonoma Horizon.heic",
        "/System/Library/Desktop Pictures/Sonoma.heic",
    ]

    /// The guide closed: give the picture's memory back. It loads again if the guide reopens.
    func release() {
        image = nil
        isCaptured = false
    }

    func load() {
        guard !isCaptured, !isLoading else { return }
        isLoading = true
        let screen = NSScreen.main
        let allowed = OnboardingState.screenRecordingAllowed() && !OnboardingState.assumeScreenRecording
        Task {
            var found: CGImage?
            if allowed, let captured = await Backdrop.wallpaper(for: screen) {
                found = captured
                isCaptured = true
            } else if image == nil {
                let file = screen.flatMap { NSWorkspace.shared.desktopImageURL(for: $0) }
                found = file.flatMap(ImageCoding.load)
                    ?? Self.fallbacks.lazy.compactMap { ImageCoding.load(URL(fileURLWithPath: $0)) }.first
            }
            if let found { image = Self.shrunk(found) }
            isLoading = false
        }
    }

    /// The pane is 460 points wide; a full-resolution wallpaper would only cost memory.
    private static func shrunk(_ image: CGImage) -> CGImage {
        let target: CGFloat = 1400
        guard CGFloat(image.width) > target else { return image }
        let scale = target / CGFloat(image.width)
        let size = CGSize(width: target, height: (CGFloat(image.height) * scale).rounded())
        guard let context = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue) else { return image }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(origin: .zero, size: size))
        return context.makeImage() ?? image
    }
}
