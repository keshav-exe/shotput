import AppKit
import SwiftUI

/// Hosts the island, edge to edge in its canvas.
final class NotchDropHostingView: NSHostingView<NotchDropView> {
    init(model: NotchDropModel) {
        super.init(rootView: NotchDropView(model: model))
        safeAreaRegions = []
    }

    @available(*, unavailable)
    required init(rootView: NotchDropView) { fatalError("init(rootView:) is not used") }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}

/// The island, hanging from the top of a canvas the size of its largest state.
struct NotchDropView: View {
    let model: NotchDropModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let size = model.size
        Group {
            if model.isMenuBar { MenuBarCard(model: model) } else { island }
        }
            .frame(width: size.width, height: size.height, alignment: .top)
            .frame(width: NotchGeometry.canvas.width, height: NotchGeometry.canvas.height, alignment: .top)
            .animation(animation, value: model.phase)
            .animation(animation, value: size)
            // Local, not preferred: in the guide's scene this mustn't turn the whole window dark.
            .modifier(DarkOnNotch(isOn: model.isHardware))
    }

    /// Opening is a soft spring with a little give; closing is quicker and settles without
    /// overshoot, since it's only getting out of the way.
    private var animation: Animation {
        if reduceMotion { return .easeOut(duration: 0.16) }
        return model.phase == .hidden ? .spring(response: 0.3, dampingFraction: 1) : .spring(response: 0.42, dampingFraction: 0.78)
    }

    private var shape: NotchShape {
        NotchShape(topRadius: model.shoulderRadius, bottomRadius: model.bottomRadius)
    }

    private var island: some View {
        ZStack(alignment: .top) {
            background
            content
                .padding(.horizontal, model.shoulderRadius)
                .clipShape(shape)
        }
        // On a notch the closed island is the notch. Elsewhere there is nothing until a drag.
        .opacity(model.phase == .hidden && !model.isHardware ? 0 : 1)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var background: some View {
        if model.isHardware, model.isPanel {
            // Solid black where the island meets the notch, so the camera cutout still
            // disappears, then easing into Liquid Glass below it.
            let band = min(0.9, model.notchSize.height / max(model.size.height, 1))
            ZStack {
                Color.clear
                    .glassEffect(.regular, in: shape)
                shape.fill(LinearGradient(
                    stops: [
                        .init(color: .black, location: 0),
                        .init(color: .black, location: band),
                        .init(color: .black.opacity(0.72), location: min(1, band + 0.22)),
                        .init(color: .black.opacity(0.58), location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                ))
            }
            .shadow(color: .black.opacity(0.32), radius: 22, y: 10)
        } else if model.isHardware {
            shape.fill(.black)
        } else {
            Color.clear
                .glassEffect(.regular, in: shape)
                .shadow(color: .black.opacity(model.isPanel ? 0.18 : 0), radius: 18, y: 8)
        }
    }

    @ViewBuilder
    private var content: some View {
        let band = model.notchSize.height
        switch model.phase {
        case .hidden:
            Color.clear.frame(height: band)
        case .armed:
            Ears(model: model)
                .frame(height: band)
                .transition(.opacity.animation(.easeOut(duration: 0.12)))
        case .near, .targeted:
            VStack(spacing: 0) {
                Color.clear.frame(height: band)
                DropWell(model: model)
                    .padding(.horizontal, 10)
                    .padding(.top, 2)
                    .padding(.bottom, 10)
            }
            .transition(.contentReveal)
        case .pinned, .alreadyPinned, .failed:
            VStack(spacing: 0) {
                Color.clear.frame(height: band)
                Moment(model: model)
                    .frame(maxHeight: .infinity)
            }
            .transition(.blurReplace)
        }
    }
}

/// The island over a hardware notch is always dark, to match the black it grows out of.
private struct DarkOnNotch: ViewModifier {
    let isOn: Bool
    func body(content: Content) -> some View {
        if isOn { content.environment(\.colorScheme, .dark) } else { content }
    }
}

private extension AnyTransition {
    /// Content waits for the island to start growing, then fades in; it leaves at once, so
    /// it's never squeezed by a shrinking shape.
    static var contentReveal: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.97, anchor: .top)).animation(.easeOut(duration: 0.2).delay(0.06)),
            removal: .opacity.animation(.easeIn(duration: 0.08))
        )
    }
}

// MARK: - Menu bar

/// The same drop target, hung under the menu bar icon when another app has the notch: a glass
/// pill that drops out of the menu bar as a drag starts, then opens into the well.
private struct MenuBarCard: View {
    let model: NotchDropModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let card = model.cardSize(for: model.phase)
        let shape = RoundedRectangle(cornerRadius: model.cardRadius, style: .continuous)
        let isHidden = model.phase == .hidden
        VStack(spacing: 0) {
            Color.clear.frame(height: model.notchSize.height + NotchDropModel.menuBarGap)
            ZStack {
                Color.clear
                    .glassEffect(.regular, in: shape)
                content
                    .clipShape(shape)
            }
            .frame(width: card.width, height: card.height)
            .shadow(color: .black.opacity(model.isPanel ? 0.2 : 0.12), radius: 18, y: 8)
            .opacity(isHidden ? 0 : 1)
            .offset(y: isHidden && !reduceMotion ? -10 : 0)
            .scaleEffect(isHidden && !reduceMotion ? 0.94 : 1, anchor: .top)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .hidden, .armed:
            HStack(spacing: 6) {
                Image(systemName: "pin.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Palette.accent.color)
                    .rotationEffect(.degrees(-18))
                Text("\(model.payload.count)")
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .contentTransition(.numericText())
            }
            .transition(.opacity.animation(.easeOut(duration: 0.12)))
            .accessibilityLabel(L("Drag to the menu bar icon to pin"))
        case .near, .targeted:
            DropWell(model: model)
                .padding(8)
                .transition(.contentReveal)
        case .pinned, .alreadyPinned, .failed:
            Moment(model: model)
                .transition(.blurReplace)
        }
    }
}

// MARK: - Ears

/// The armed notch: a pin on the left, how many are coming on the right, the notch between.
private struct Ears: View {
    let model: NotchDropModel

    var body: some View {
        HStack(spacing: 0) {
            Image(systemName: "pin.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Palette.accent.color)
                .rotationEffect(.degrees(-18))
                .padding(.trailing, 8)
                .frame(width: NotchDropModel.earWidth, alignment: .trailing)
            Color.clear
                .frame(width: model.notchSize.width)
            Text("\(model.payload.count)")
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                .foregroundStyle(.primary)
                .contentTransition(.numericText())
                .padding(.leading, 8)
                .frame(width: NotchDropModel.earWidth, alignment: .leading)
        }
        .accessibilityLabel(L("Drag to the notch to pin"))
    }
}

// MARK: - Well

/// Where the drag goes: a dashed well with what's being dragged, fanned on the left.
private struct DropWell: View {
    let model: NotchDropModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isTargeted: Bool { model.phase == .targeted }
    private var accent: Color { Palette.accent.color }

    var body: some View {
        let well = RoundedRectangle(cornerRadius: 16, style: .continuous)
        HStack(spacing: 14) {
            FannedIcons(payload: model.payload, isLifted: isTargeted)
                .frame(width: 52, height: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text(isTargeted ? L("Let go to pin") : L("Drop to pin"))
                    .font(.system(size: 13, weight: .semibold))
                    .contentTransition(.opacity)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 3) {
                Image(systemName: "pin")
                    .font(.system(size: 9.5, weight: .semibold))
                Text("\(model.total)/\(PinStore.limit)")
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
            }
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 7)
            .frame(height: 20)
            .background(Color.primary.opacity(0.07), in: .capsule)
            .help(model.total >= PinStore.limit ? L("The oldest pin makes room") : L("Pins kept in the menu bar"))
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(well.fill(isTargeted ? accent.opacity(0.16) : Color.primary.opacity(0.04)))
        .overlay(
            well.strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                .foregroundStyle(isTargeted ? accent : Color.primary.opacity(0.22))
        )
        .scaleEffect(isTargeted && !reduceMotion ? 1.015 : 1)
        .animation(.spring(duration: 0.28, bounce: 0.25), value: isTargeted)
        .accessibilityElement(children: .combine)
    }

    private var subtitle: String {
        let payload = model.payload
        if payload.capture != nil { return L("This screenshot") }
        if payload.count == 1 { return payload.name ?? L("1 item") }
        return String(format: L("%d items"), payload.count)
    }
}

/// Up to three icons in a loose fan, which spreads as the drag comes over the well.
private struct FannedIcons: View {
    let payload: DragPayload
    let isLifted: Bool

    var body: some View {
        let icons = Array(payload.icons.prefix(3))
        ZStack {
            ForEach(Array(icons.enumerated()), id: \.offset) { index, icon in
                let spread = CGFloat(index) - CGFloat(icons.count - 1) / 2
                tile(icon)
                    .rotationEffect(.degrees(Double(spread) * (isLifted ? 12 : 7)))
                    .offset(x: spread * (isLifted ? 9 : 5), y: isLifted ? -2 : 0)
                    .zIndex(Double(icons.count - index))
            }
        }
        .animation(.spring(duration: 0.32, bounce: 0.3), value: isLifted)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func tile(_ icon: NSImage) -> some View {
        if payload.capture != nil {
            // A screenshot shows as itself, framed like a print.
            Image(nsImage: icon)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 46, height: 32)
                .clipShape(.rect(cornerRadius: 5, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(.white.opacity(0.7), lineWidth: 1.5))
                .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
        } else {
            Image(nsImage: icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 40, height: 40)
                .shadow(color: .black.opacity(0.25), radius: 3, y: 1.5)
        }
    }
}

// MARK: - Moment

/// What happened, said once, before the island closes over it.
private struct Moment: View {
    let model: NotchDropModel

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 32, height: 32)
                .background(tint.opacity(0.16), in: .circle)
                .symbolEffect(.bounce, value: model.phase)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .monospacedDigit()
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .accessibilityElement(children: .combine)
    }

    private var symbol: String {
        switch model.phase {
        case .alreadyPinned: "pin.fill"
        case .failed: "exclamationmark"
        default: "checkmark"
        }
    }

    private var tint: Color {
        switch model.phase {
        case .alreadyPinned: Palette.accent.color
        case .failed: .yellow
        default: .green
        }
    }

    private var title: String {
        switch model.phase {
        case .pinned(let count): count == 1 ? L("Pinned") : String(format: L("Pinned %d items"), count)
        case .alreadyPinned: L("Already pinned")
        default: L("Couldn’t pin that")
        }
    }

    private var detail: String {
        switch model.phase {
        case .pinned: String(format: L("In the menu bar, %d of %d"), model.total, PinStore.limit)
        case .alreadyPinned: L("It’s in the menu bar")
        default: L("Only files and pictures can be pinned")
        }
    }
}
