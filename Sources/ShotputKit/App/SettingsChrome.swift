import AppKit
import SwiftUI

/// Every pane is a grouped form, the way System Settings lays itself out: rounded groups, a
/// label on the left and its control on the right. One size for every pane, so the window never
/// jumps as you switch tabs; a long pane scrolls.
struct SettingsPage<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        Form {
            content
        }
        .formStyle(.grouped)
        .frame(width: SettingsMetrics.width, height: SettingsMetrics.height)
    }
}

enum SettingsMetrics {
    static let width: CGFloat = 620
    /// A var so development renders can show a pane whole.
    nonisolated(unsafe) static var height: CGFloat = 600
}

extension Palette {
    /// Vivid hues for icons and marks only, deeper on paper so they keep their contrast.
    enum Vivid {
        static let orange = NSColor.dynamic(light: 0xE86700, dark: 0xFF8717).color
        static let pink = NSColor.dynamic(light: 0xE03694, dark: 0xFF5BB3).color
        static let violet = NSColor.dynamic(light: 0x8848E1, dark: 0xAC70FF).color
        static let blue = NSColor.dynamic(light: 0x0278E7, dark: 0x3D9EFF).color
        static let green = NSColor.dynamic(light: 0x00A33A, dark: 0x37DD66).color
        static let cyan = NSColor.dynamic(light: 0x00A0BA, dark: 0x00D6F5).color
        static let yellow = NSColor.dynamic(light: 0xDBA000, dark: 0xFFCF00).color
        static let red = NSColor.dynamic(light: 0xE23532, dark: 0xFF423E).color
        static let gray = Color(white: 0.5)
    }
}

// MARK: - Icons

/// A setting's icon: a flat tinted square holding a white symbol, like the sidebar of System
/// Settings.
struct SettingsIcon: View {
    let symbol: String
    var tint: Color = .gray
    var size: CGFloat = 22

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(tint, in: .rect(cornerRadius: size * 0.27, style: .continuous))
            .accessibilityHidden(true)
    }
}

// MARK: - Rows

/// A row's label: icon, title, and an optional line explaining it.
struct SettingsLabel: View {
    let title: String
    var subtitle: String?
    var symbol: String?
    var tint: Color = .gray

    var body: some View {
        HStack(spacing: 10) {
            if let symbol {
                SettingsIcon(symbol: symbol, tint: tint)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

/// A label on the left, anything on the right.
struct SettingsRow<Trailing: View>: View {
    let title: String
    var subtitle: String?
    var symbol: String?
    var tint: Color = .gray
    @ViewBuilder let trailing: Trailing

    var body: some View {
        LabeledContent {
            trailing
        } label: {
            SettingsLabel(title: title, subtitle: subtitle, symbol: symbol, tint: tint)
        }
    }
}

/// An on/off setting, as a switch on the right.
struct SettingsToggle: View {
    let title: String
    var subtitle: String?
    var symbol: String?
    var tint: Color = .gray
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            SettingsLabel(title: title, subtitle: subtitle, symbol: symbol, tint: tint)
        }
        .toggleStyle(.switch)
        .controlSize(.small)
    }
}

/// A choice from a short list, as a pop-up menu on the right.
struct SettingsPicker<Value: Hashable & Identifiable>: View {
    let title: String
    var subtitle: String?
    var symbol: String?
    var tint: Color = .gray
    let options: [Value]
    let label: (Value) -> String
    @Binding var selection: Value

    var body: some View {
        Picker(selection: $selection) {
            ForEach(options) { Text(label($0)).tag($0) }
        } label: {
            SettingsLabel(title: title, subtitle: subtitle, symbol: symbol, tint: tint)
        }
    }
}

/// A small coloured status: "Allowed", "Watching".
struct StatusBadge: View {
    let text: String
    var tint: Color = Palette.Vivid.green

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(tint).frame(width: 6, height: 6)
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}

extension View {
    /// The quiet line under a group.
    func settingsFooter() -> some View {
        font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Picture cards

/// A choice shown as a little picture of what it does, with a tick under the one picked.
struct PictureCard<Picture: View>: View {
    let title: String
    let isPicked: Bool
    let action: () -> Void
    @ViewBuilder let picture: Picture
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                picture
                    .frame(height: 64)
                    .frame(maxWidth: .infinity)
                    .background(Color.primary.opacity(0.05), in: .rect(cornerRadius: 8, style: .continuous))
                    .clipShape(.rect(cornerRadius: 8, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(isPicked ? Color.accentColor : Color.primary.opacity(isHovered ? 0.2 : 0.1), lineWidth: isPicked ? 2 : 1)
                    }
                HStack(spacing: 5) {
                    Image(systemName: isPicked ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isPicked ? Color.accentColor : Color.secondary)
                    Text(title)
                        .font(.callout.weight(isPicked ? .semibold : .regular))
                        .lineLimit(1)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.15), value: isHovered)
        .accessibilityAddTraits(isPicked ? .isSelected : [])
    }
}

// MARK: - Illustrations

/// The pieces every picture is drawn from: a desktop with its menu bar, window skeletons, and
/// screenshots in miniature. Drawn, not bitmaps, so they stay crisp and follow light and dark.
private enum Sketch {
    static let line = Color.primary.opacity(0.13)
    static let faint = Color.primary.opacity(0.07)
    static let menuBar: CGFloat = 7
}

/// A Mac screen in miniature: the desktop, the menu bar along the top, then whatever's drawn
/// over it, pinned to the top so every card lines up the same.
private struct MiniDesktop<Content: View>: View {
    var alignment: Alignment = .top
    @ViewBuilder let content: Content

    var body: some View {
        ZStack(alignment: .top) {
            Sketch.faint
            HStack(spacing: 4) {
                Circle().fill(Sketch.line).frame(width: 3.5, height: 3.5)
                ForEach([10.0, 8, 12], id: \.self) { width in
                    Capsule().fill(Sketch.line).frame(width: width, height: 2.5)
                }
                Spacer()
                Capsule().fill(Sketch.line).frame(width: 14, height: 2.5)
            }
            .padding(.horizontal, 7)
            .frame(height: Sketch.menuBar)
            .background(Color.primary.opacity(0.06))
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// An app window as a skeleton: a title bar with its three dots, a few lines of content.
private struct MiniWindow: View {
    var width: CGFloat = 86
    var height: CGFloat = 40
    var lines = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 2.5) {
                ForEach(0 ..< 3) { _ in Circle().fill(Sketch.line).frame(width: 3.5, height: 3.5) }
            }
            ForEach(0 ..< lines, id: \.self) { index in
                Capsule().fill(Sketch.line).frame(width: width * [0.7, 0.5, 0.6][index % 3], height: 3)
            }
            Spacer(minLength: 0)
        }
        .padding(5)
        .frame(width: width, height: height, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor), in: .rect(cornerRadius: 4, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(Sketch.line, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.1), radius: 2, y: 1)
    }
}

/// A screenshot in miniature: a little picture of a window, in a rounded frame.
private struct MiniShot: View {
    var width: CGFloat = 34
    var height: CGFloat = 22
    var tint: Color = Palette.Vivid.blue

    var body: some View {
        RoundedRectangle(cornerRadius: 3.5, style: .continuous)
            .fill(LinearGradient(colors: [tint.opacity(0.85), tint.opacity(0.6)], startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: max(2, height * 0.1)) {
                    Capsule().fill(.white.opacity(0.85)).frame(width: width * 0.45, height: max(2, height * 0.1))
                    Capsule().fill(.white.opacity(0.5)).frame(width: width * 0.3, height: max(1.5, height * 0.08))
                }
                .padding(width * 0.12)
            }
            .overlay(RoundedRectangle(cornerRadius: 3.5, style: .continuous).strokeBorder(.white.opacity(0.9), lineWidth: 1))
            .frame(width: width, height: height)
            .shadow(color: .black.opacity(0.22), radius: 2, y: 1)
    }
}

/// Two screenshots stacked as previews do, the newer in front.
private struct MiniStack: View {
    var width: CGFloat = 30
    var height: CGFloat = 19
    /// Toward the screen's top, so the card behind peeks out downward.
    var fromTop = false
    var isLit = true

    var body: some View {
        ZStack {
            MiniShot(width: width, height: height, tint: isLit ? Palette.Vivid.violet : .gray)
                .scaleEffect(0.86)
                .offset(y: fromTop ? 5 : -5)
            MiniShot(width: width, height: height, tint: isLit ? Palette.Vivid.blue : .gray)
        }
    }
}

/// What happens after a capture, as three pictures: a thumbnail, the editor, or the clipboard.
struct AfterCapturePicker: View {
    @Binding var selection: Settings.AfterCapture

    var body: some View {
        HStack(spacing: 12) {
            ForEach(Settings.AfterCapture.allCases) { choice in
                PictureCard(title: choice.title, isPicked: selection == choice, action: {
                    withAnimation(.smooth(duration: 0.25)) { selection = choice }
                }) {
                    picture(choice)
                }
            }
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private func picture(_ choice: Settings.AfterCapture) -> some View {
        switch choice {
        case .preview:
            // The desktop as it was, and the capture waiting in the corner.
            MiniDesktop {
                ZStack(alignment: .bottomTrailing) {
                    MiniWindow(width: 70, height: 36)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .padding(.leading, 12)
                        .padding(.top, 13)
                    MiniStack()
                        .padding(.trailing, 9)
                        .padding(.bottom, 7)
                }
            }
        case .editor:
            // The editor: the capture, marked up, under its bar of inks.
            MiniDesktop {
                VStack(spacing: 3) {
                    HStack(spacing: 3) {
                        ForEach([Palette.Vivid.red, Palette.Vivid.yellow, Palette.Vivid.green, Palette.Vivid.blue], id: \.self) { color in
                            Circle().fill(color).frame(width: 4.5, height: 4.5)
                        }
                    }
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2.5)
                    .background(Color(nsColor: .windowBackgroundColor), in: .capsule)
                    .overlay(Capsule().strokeBorder(Sketch.line, lineWidth: 0.5))
                    MiniShot(width: 58, height: 34)
                        .overlay {
                            ZStack {
                                RoundedRectangle(cornerRadius: 2)
                                    .strokeBorder(Palette.Vivid.red, lineWidth: 1.2)
                                    .frame(width: 18, height: 10)
                                    .offset(x: 12, y: 6)
                                Image(systemName: "arrow.down.right")
                                    .font(.system(size: 9, weight: .heavy))
                                    .foregroundStyle(Palette.Vivid.red)
                                    .offset(x: -6, y: -2)
                            }
                        }
                }
                .padding(.top, 11)
            }
        case .clipboard:
            // Nothing on screen but the paste: straight into the conversation you're in.
            MiniDesktop {
                VStack(alignment: .trailing, spacing: 4) {
                    MiniShot(width: 32, height: 19)
                        .padding(3)
                        .background(Palette.Vivid.blue.opacity(0.18), in: .rect(cornerRadius: 5, style: .continuous))
                    HStack(spacing: 3) {
                        Text("⌘V")
                            .font(.system(size: 7.5, weight: .semibold, design: .rounded))
                            .padding(.horizontal, 3)
                            .padding(.vertical, 1)
                            .background(Color(nsColor: .windowBackgroundColor), in: .rect(cornerRadius: 2.5))
                            .overlay(RoundedRectangle(cornerRadius: 2.5).strokeBorder(Sketch.line, lineWidth: 0.5))
                        Capsule().fill(Sketch.line).frame(width: 30, height: 3)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(5)
                .frame(width: 92, height: 46)
                .background(Color(nsColor: .windowBackgroundColor), in: .rect(cornerRadius: 4, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(Sketch.line, lineWidth: 0.5))
                .shadow(color: .black.opacity(0.1), radius: 2, y: 1)
                .padding(.top, 11)
            }
        }
    }
}

/// The four corners of a screen, with the preview stack drawn in the one picked.
struct CornerPicker: View {
    @Binding var selection: Settings.Corner

    var body: some View {
        HStack(spacing: 10) {
            ForEach([Settings.Corner.topLeft, .topRight, .bottomLeft, .bottomRight]) { corner in
                PictureCard(title: corner.title, isPicked: selection == corner, action: {
                    withAnimation(.smooth(duration: 0.25)) { selection = corner }
                }) {
                    screen(corner, isPicked: selection == corner)
                }
            }
        }
        .padding(.vertical, 6)
    }

    private func screen(_ corner: Settings.Corner, isPicked: Bool) -> some View {
        let alignment: Alignment = switch corner {
        case .topLeft: .topLeading
        case .topRight: .topTrailing
        case .bottomLeft: .bottomLeading
        case .bottomRight: .bottomTrailing
        }
        return MiniDesktop(alignment: alignment) {
            MiniStack(width: 28, height: 18, fromTop: corner.isTop, isLit: isPicked)
                .opacity(isPicked ? 1 : 0.55)
                .padding(.horizontal, 8)
                .padding(.top, corner.isTop ? Sketch.menuBar + 7 : 0)
                .padding(.bottom, corner.isTop ? 0 : 9)
        }
    }
}

/// Where pins are kept: the notch, or under the menu bar icon.
struct PinTargetPicker: View {
    @Binding var selection: Settings.PinTarget

    var body: some View {
        HStack(spacing: 12) {
            ForEach(Settings.PinTarget.allCases) { target in
                PictureCard(title: target.title, isPicked: selection == target, action: {
                    withAnimation(.smooth(duration: 0.25)) { selection = target }
                }) {
                    picture(target)
                }
            }
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private func picture(_ target: Settings.PinTarget) -> some View {
        switch target {
        case .notch:
            // The tray, open under the notch, hanging from the very top of the screen.
            MiniDesktop {
                UnevenRoundedRectangle(bottomLeadingRadius: 10, bottomTrailingRadius: 10, style: .continuous)
                    .fill(Color(white: 0.07))
                    .frame(width: 128, height: 42)
                    .overlay(alignment: .top) {
                        VStack(spacing: 5) {
                            Capsule().fill(Color.black).frame(width: 30, height: 5)
                                .overlay(Circle().fill(Color(white: 0.2)).frame(width: 3, height: 3))
                            HStack(spacing: 4) {
                                ForEach(0 ..< 3) { index in
                                    MiniShot(width: 28, height: 18, tint: index == 1 ? Palette.Vivid.violet : Palette.Vivid.blue)
                                }
                            }
                        }
                        .padding(.top, 1)
                    }
            }
        case .menuBar:
            // A card dropped from Shotput's icon at the right of the menu bar.
            MiniDesktop {
                ZStack(alignment: .topTrailing) {
                    Color.clear
                    RoundedRectangle(cornerRadius: 1.5).fill(Color.accentColor)
                        .frame(width: 7, height: 5)
                        .padding(.top, 1)
                        .padding(.trailing, 28)
                    HStack(spacing: 4) {
                        MiniShot(width: 24, height: 16)
                        MiniShot(width: 24, height: 16, tint: Palette.Vivid.violet)
                    }
                    .padding(6)
                    .background(Color(nsColor: .windowBackgroundColor), in: .rect(cornerRadius: 6, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Sketch.line, lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.15), radius: 3, y: 1)
                    .padding(.top, Sketch.menuBar + 4)
                    .padding(.trailing, 10)
                }
            }
        }
    }
}

/// A slider that stops at each of a list of values, with the value's name beside it.
struct SteppedSlider: View {
    let values: [Double]
    @Binding var value: Double
    let label: (Double) -> String

    private var index: Binding<Double> {
        Binding(
            get: { Double(values.firstIndex(of: value) ?? values.firstIndex { $0 >= value } ?? values.count - 1) },
            set: { value = values[min(max(Int($0.rounded()), 0), values.count - 1)] }
        )
    }

    var body: some View {
        HStack(spacing: 10) {
            Slider(value: index, in: 0 ... Double(values.count - 1), step: 1)
                .frame(width: 170)
            Text(label(value))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 112, alignment: .trailing)
                .contentTransition(.numericText())
                .animation(.snappy(duration: 0.2), value: value)
        }
    }
}
