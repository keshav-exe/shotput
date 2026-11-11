import Carbon.HIToolbox
import SwiftUI

/// The welcome guide's opening: a few seconds of Shotput doing its one job, on a miniature
/// desktop. Press the shortcut, the screen freezes, drag over a card, it lands in the corner,
/// paste it into a chat. One screenshot travels the whole way, so the eye follows a single thing.
struct WelcomeFilm: View {
    static let stage = CGSize(width: 504, height: 268)

    @ObservedObject private var settings = Settings.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Scene state, stepped through by `play()`.
    @State private var caption = Caption.press
    @State private var keys: Shortcut?
    @State private var pressed: Int?
    @State private var frozen = false
    @State private var pointer = CGPoint(x: 214, y: 150)
    @State private var crosshair = false
    @State private var selection: CGRect?
    @State private var flash = false
    @State private var shot: ShotPlace = .hidden
    @State private var sent = false

    private enum ShotPlace { case hidden, selection, corner, chat }

    private enum Caption: String {
        case press = "Press the shortcut in any app"
        case drag = "The screen holds still while you drag"
        case copied = "It's on the clipboard already"
        case paste = "Paste it wherever you're working"
    }

    // Layout of the miniature desktop.
    private let appWindow = CGRect(x: 26, y: 34, width: 286, height: 204)
    private let card = CGRect(x: 48, y: 80, width: 200, height: 84)
    private let chatWindow = CGRect(x: 328, y: 40, width: 152, height: 152)
    private var chatInput: CGRect { CGRect(x: chatWindow.minX + 10, y: chatWindow.maxY - 30, width: chatWindow.width - 20, height: 20) }
    private var bubble: CGRect { CGRect(x: chatWindow.maxX - 122, y: chatWindow.minY + 58, width: 112, height: 47) }
    private var corner: CGRect { CGRect(x: Self.stage.width - 114, y: Self.stage.height - 58, width: 100, height: 42) }
    private var selectionTarget: CGRect { card.insetBy(dx: -6, dy: -6) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            desktop
            if frozen { freeze.transition(.opacity) }
            if let selection { selectionChrome(selection) }
            if flash, let selection {
                Rectangle().fill(.white.opacity(0.55))
                    .frame(width: selection.width, height: selection.height)
                    .offset(x: selection.minX, y: selection.minY)
                    .allowsHitTesting(false)
            }
            shotView
            pointerView
            overlayKeys
            subtitle
        }
        .frame(width: Self.stage.width, height: Self.stage.height, alignment: .topLeading)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        // The miniature desktop is a picture of a light Mac, whatever the real one is set to.
        .environment(\.colorScheme, .light)
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Palette.ink.color.opacity(0.1)))
        .accessibilityElement()
        .accessibilityLabel("A short animation: press the shortcut, drag over part of the screen, and paste the screenshot into a chat.")
        .task(id: settings.shortcuts[.area]) { await play() }
    }

    // MARK: Desktop

    private var desktop: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(colors: [Color(nsColor: NSColor(hex: 0xC9D6E3)), Color(nsColor: NSColor(hex: 0xE6DED2))],
                           startPoint: .top, endPoint: .bottom)
            // Menu bar, with Shotput's icon at the right.
            HStack(spacing: 6) {
                Image(systemName: "apple.logo").font(.system(size: 8, weight: .semibold))
                Capsule().fill(.black.opacity(0.35)).frame(width: 24, height: 4)
                Capsule().fill(.black.opacity(0.2)).frame(width: 18, height: 4)
                Spacer()
                Icon.capture.view(size: 8, weight: .bold).opacity(frozen ? 1 : 0.75)
                Capsule().fill(.black.opacity(0.2)).frame(width: 30, height: 4)
            }
            .foregroundStyle(.black.opacity(0.7))
            .padding(.horizontal, 10)
            .frame(width: Self.stage.width, height: 16)
            .background(.white.opacity(0.45))

            miniWindow(appWindow) {
                VStack(alignment: .leading, spacing: 7) {
                    Capsule().fill(Palette.ink.color.opacity(0.5)).frame(width: 90, height: 6)
                    Capsule().fill(Palette.ink.color.opacity(0.18)).frame(width: 150, height: 4)
                }
                .padding(.leading, 22).padding(.top, 14)
            }
            CardMock().frame(width: card.width, height: card.height).offset(x: card.minX, y: card.minY)
            VStack(alignment: .leading, spacing: 5) {
                ForEach([170, 210, 140], id: \.self) { width in
                    Capsule().fill(Palette.ink.color.opacity(0.12)).frame(width: CGFloat(width), height: 4)
                }
            }
            .offset(x: card.minX, y: card.maxY + 18)

            miniWindow(chatWindow) {
                VStack(alignment: .leading, spacing: 6) {
                    Capsule().fill(Palette.ink.color.opacity(0.14)).frame(width: 84, height: 16)
                        .overlay(alignment: .leading) {
                            Capsule().fill(Palette.ink.color.opacity(0.3)).frame(width: 54, height: 3).padding(.leading, 8)
                        }
                }
                .padding(.leading, 10).padding(.top, 12)
            }
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Palette.ink.color.opacity(0.15))
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white))
                .frame(width: chatInput.width, height: chatInput.height)
                .overlay(alignment: .leading) {
                    Text(sent ? "" : "Message").font(.system(size: 8)).foregroundStyle(.tertiary).padding(.leading, 8)
                }
                .offset(x: chatInput.minX, y: chatInput.minY)
        }
    }

    private func miniWindow(_ frame: CGRect, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                ForEach([0xFF5F57, 0xFEBC2E, 0x28C840], id: \.self) { hex in
                    Circle().fill(Color(nsColor: NSColor(hex: UInt(hex)))).frame(width: 6, height: 6)
                }
            }
            .padding(.leading, 8)
            .frame(height: 18)
            content()
            Spacer(minLength: 0)
        }
        .frame(width: frame.width, height: frame.height, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color(nsColor: NSColor(hex: 0xFBFBF9))))
        .shadow(color: .black.opacity(0.14), radius: 10, y: 4)
        .offset(x: frame.minX, y: frame.minY)
    }

    // MARK: Capture chrome

    private var freeze: some View {
        Rectangle()
            .fill(.black.opacity(0.32))
            .mask {
                ZStack(alignment: .topLeading) {
                    Rectangle()
                    if let selection {
                        Rectangle().frame(width: selection.width, height: selection.height)
                            .offset(x: selection.minX, y: selection.minY)
                            .blendMode(.destinationOut)
                    }
                }
                .compositingGroup()
            }
            .allowsHitTesting(false)
    }

    private func selectionChrome(_ rect: CGRect) -> some View {
        ZStack(alignment: .topLeading) {
            Rectangle().strokeBorder(.white, lineWidth: 1)
                .frame(width: rect.width, height: rect.height)
                .offset(x: rect.minX, y: rect.minY)
            Text("\(Int(rect.width * 2)) × \(Int(rect.height * 2))")
                .font(.system(size: 8, weight: .medium).monospacedDigit())
                .foregroundStyle(.white)
                .contentTransition(.numericText())
                .padding(.horizontal, 5).padding(.vertical, 2)
                .background(Capsule().fill(.black.opacity(0.7)))
                .fixedSize()
                .offset(x: rect.maxX - 50, y: rect.maxY + 5)
        }
        .allowsHitTesting(false)
    }

    /// The one screenshot: cut from the card, settled in the corner, then sent in the chat.
    @ViewBuilder private var shotView: some View {
        if shot != .hidden {
            let frame: CGRect = switch shot {
            case .selection: selectionTarget
            case .corner: corner
            case .chat: bubble
            case .hidden: .zero
            }
            // Exactly what was selected: the card and the sliver of window around it.
            CardMock()
                .padding(6)
                .background(Color(nsColor: NSColor(hex: 0xFBFBF9)))
                .frame(width: selectionTarget.width, height: selectionTarget.height)
                .scaleEffect(frame.width / selectionTarget.width, anchor: .topLeading)
                .frame(width: frame.width, height: frame.height, alignment: .topLeading)
                .clipShape(RoundedRectangle(cornerRadius: shot == .selection ? 0 : 7, style: .continuous))
                .overlay(alignment: .bottomTrailing) {
                    if shot == .chat {
                        Image(systemName: "checkmark").font(.system(size: 7, weight: .bold)).foregroundStyle(.white)
                            .padding(3).background(Circle().fill(Palette.accent.color)).offset(x: 4, y: 4)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .shadow(color: .black.opacity(shot == .selection ? 0 : 0.25), radius: 8, y: 3)
                .offset(x: frame.minX, y: frame.minY)
                .allowsHitTesting(false)
        }
    }

    private var pointerView: some View {
        Group {
            if crosshair {
                ZStack {
                    Rectangle().frame(width: 1, height: 14)
                    Rectangle().frame(width: 14, height: 1)
                }
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.6), radius: 1)
            } else {
                Image(systemName: "cursorarrow")
                    .font(.system(size: 15))
                    .foregroundStyle(.black)
                    .background(Image(systemName: "cursorarrow.fill").font(.system(size: 15)).foregroundStyle(.white))
                    .shadow(color: .black.opacity(0.25), radius: 1.5, y: 1)
                    .offset(x: 5, y: 7)
            }
        }
        .position(pointer)
        .allowsHitTesting(false)
    }

    @ViewBuilder private var overlayKeys: some View {
        if let keys {
            KeyCaps(shortcut: keys, size: .regular, pressed: pressed)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.ultraThinMaterial))
                .position(x: Self.stage.width / 2, y: 200)
                .transition(.scale(scale: 0.9).combined(with: .opacity))
        }
    }

    private var subtitle: some View {
        Text(caption.rawValue)
            .font(.callout.weight(.medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Capsule().fill(.black.opacity(0.62)))
            .id(caption)
            .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: 6)), removal: .opacity))
            .frame(width: Self.stage.width, height: Self.stage.height, alignment: .bottom)
            .padding(.bottom, 14)
            .frame(width: Self.stage.width, height: Self.stage.height, alignment: .bottom)
    }

    // MARK: Direction

    private func play() async {
        let area = settings.shortcuts[.area] ?? HotAction.area.defaultShortcut
        let paste = Shortcut(keyCode: kVK_ANSI_V, [.command])
        guard !reduceMotion else {
            // One still frame that tells the whole story.
            caption = .paste
            shot = .chat
            sent = true
            return
        }

        while !Task.isCancelled {
            reset()
            await wait(0.6)

            // 1. The shortcut, typed one key at a time.
            withAnimation(.snappy(duration: 0.2)) { keys = area }
            await wait(0.35)
            for index in 0 ..< keyCount(area) {
                withAnimation(.snappy(duration: 0.1)) { pressed = index }
                await wait(0.11)
            }
            await wait(0.2)
            withAnimation(.easeOut(duration: 0.2)) {
                keys = nil
                pressed = nil
                frozen = true
                crosshair = true
            }

            // 2. Drag out a selection over the card.
            withAnimation(.easeOut(duration: 0.2)) { caption = .drag }
            withAnimation(.easeInOut(duration: 0.45)) { pointer = selectionTarget.origin }
            await wait(0.55)
            selection = CGRect(origin: selectionTarget.origin, size: .zero)
            withAnimation(.timingCurve(0.3, 0, 0.2, 1, duration: 0.8)) {
                selection = selectionTarget
                pointer = CGPoint(x: selectionTarget.maxX, y: selectionTarget.maxY)
            }
            await wait(0.95)

            // 3. Let go: shutter, the screen comes back, the shot settles in the corner.
            flash = true
            shot = .selection
            withAnimation(.easeOut(duration: 0.25)) { flash = false }
            await wait(0.12)
            withAnimation(.easeOut(duration: 0.2)) {
                frozen = false
                selection = nil
                crosshair = false
                caption = .copied
            }
            withAnimation(.spring(duration: 0.55, bounce: 0.18)) { shot = .corner }
            await wait(1.2)

            // 4. Over to the chat, paste, and it sends.
            withAnimation(.easeInOut(duration: 0.55)) {
                pointer = CGPoint(x: chatInput.midX, y: chatInput.midY)
                caption = .paste
            }
            await wait(0.6)
            withAnimation(.snappy(duration: 0.2)) { keys = paste }
            await wait(0.25)
            withAnimation(.snappy(duration: 0.1)) { pressed = 0 }
            await wait(0.1)
            withAnimation(.snappy(duration: 0.1)) { pressed = 1 }
            await wait(0.25)
            withAnimation(.snappy(duration: 0.2)) {
                keys = nil
                pressed = nil
            }
            withAnimation(.spring(duration: 0.6, bounce: 0.22)) {
                shot = .chat
                sent = true
            }
            await wait(2.6)
            withAnimation(.easeIn(duration: 0.3)) { shot = .hidden }
            await wait(0.4)
        }
    }

    private func reset() {
        caption = .press
        keys = nil
        pressed = nil
        frozen = false
        crosshair = false
        selection = nil
        flash = false
        shot = .hidden
        sent = false
        withAnimation(.easeInOut(duration: 0.5)) { pointer = CGPoint(x: 214, y: 150) }
    }

    private func keyCount(_ shortcut: Shortcut) -> Int {
        [NSEvent.ModifierFlags.control, .option, .shift, .command].filter { shortcut.flags.contains($0) }.count + 1
    }

    private func wait(_ seconds: Double) async {
        try? await Task.sleep(for: .seconds(seconds))
    }
}

/// The bit of interface the film captures: a small card with a button.
private struct CardMock: View {
    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(LinearGradient(colors: [Color(nsColor: NSColor(hex: 0xF7B267)), Color(nsColor: NSColor(hex: 0xE5484D))],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 52, height: 52)
            VStack(alignment: .leading, spacing: 6) {
                Capsule().fill(Palette.ink.color.opacity(0.7)).frame(width: 84, height: 6)
                Capsule().fill(Palette.ink.color.opacity(0.25)).frame(width: 110, height: 4)
                Capsule().fill(Palette.accent.color).frame(width: 46, height: 14)
                    .overlay(Capsule().fill(.white.opacity(0.9)).frame(width: 24, height: 3))
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Palette.ink.color.opacity(0.08)))
    }
}
