import SwiftUI

/// Floating colour, weight, and fill controls, with a toast slot above them.
struct StyleBar: View {
    @ObservedObject var model: EditorModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: Metrics.spacingS) {
            if let toast = model.toast {
                Text(toast)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Palette.ink.color)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .glassEffect(.regular, in: .capsule)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.92)))
            }

            HStack(spacing: 12) {
                HStack(spacing: 2) {
                    ForEach(InkColor.allCases, id: \.self) { ink in
                        Swatch(ink: ink, isSelected: model.color == ink) { model.setColor(ink) }
                    }
                }
                .disabled(!model.styleTool.supportsColor)
                .opacity(model.styleTool.supportsColor ? 1 : 0.35)

                divider

                HStack(spacing: 2) {
                    ForEach(Weight.allCases, id: \.self) { weight in
                        WeightButton(weight: weight, isSelected: model.weight == weight) { model.setWeight(weight) }
                    }
                }
                .disabled(!model.styleTool.supportsWeight)
                .opacity(model.styleTool.supportsWeight ? 1 : 0.35)

                divider

                BarButton(
                    icon: model.filled ? .fill : .unfilled,
                    label: model.styleTool == .redact ? "Solid block" : "Fill",
                    isSelected: model.filled
                ) { model.setFilled(!model.filled) }
                    .disabled(!model.styleTool.supportsFill)
                    .opacity(model.styleTool.supportsFill ? 1 : 0.35)

                divider

                HStack(spacing: 2) {
                    BarButton(icon: .undo, label: "Undo", isSelected: false) { model.undo() }
                        .disabled(!model.canUndo)
                        .opacity(model.canUndo ? 1 : 0.35)
                    BarButton(icon: .redo, label: "Redo", isSelected: false) { model.redo() }
                        .disabled(!model.canRedo)
                        .opacity(model.canRedo ? 1 : 0.35)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .glassEffect(.regular, in: .capsule)
        }
        .padding(Metrics.spacingS)
        .animation(.snappy(duration: 0.25), value: model.toast)
        .animation(.snappy(duration: 0.18), value: model.color)
        .animation(.snappy(duration: 0.18), value: model.weight)
    }

    private var divider: some View {
        Rectangle()
            .fill(Palette.ink.color.opacity(0.12))
            .frame(width: 1, height: 18)
    }
}

private struct Swatch: View {
    let ink: InkColor
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .strokeBorder(Palette.ink.color, lineWidth: 2)
                    .opacity(isSelected ? 1 : 0)
                Circle()
                    .fill(Color(nsColor: ink.nsColor))
                    .overlay(Circle().strokeBorder(Palette.ink.color.opacity(0.18), lineWidth: 0.5))
                    .padding(isSelected ? 4 : 3)
            }
            .frame(width: 28, height: 28)
            .contentShape(Circle())
        }
        .buttonStyle(CircleButtonStyle())
        .help("\(ink.name) (\(ink.rawValue + 1))")
        .accessibilityLabel(ink.name)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct WeightButton: View {
    let weight: Weight
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Capsule()
                .fill(Palette.ink.color)
                .frame(width: 14, height: [2, 3.5, 5.5, 8][weight.rawValue])
                .frame(width: 28, height: 28)
                .background(Circle().fill(Palette.ink.color.opacity(isSelected ? 0.12 : 0)))
                .contentShape(Circle())
        }
        .buttonStyle(CircleButtonStyle())
        .help(weight.name)
        .accessibilityLabel("\(weight.name) weight")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct BarButton: View {
    let icon: Icon
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            icon.view(size: 13, weight: .medium)
                .foregroundStyle(isSelected ? Palette.accent.color : Palette.ink.color)
                .frame(width: 28, height: 28)
                .background(Circle().fill(Palette.accent.color.opacity(isSelected ? 0.14 : 0)))
                .contentShape(Circle())
        }
        .buttonStyle(CircleButtonStyle())
        .help(label)
        .accessibilityLabel(label)
    }
}

/// The style bar's hover and press, matching the toolbar's buttons: a faint circle on hover, a
/// firmer one and a slight press while held.
private struct CircleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { CircleButton(configuration: configuration) }

    private struct CircleButton: View {
        let configuration: Configuration
        @State private var hovered = false
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            configuration.label
                .background(Circle().fill(Palette.ink.color.opacity(configuration.isPressed ? 0.14 : hovered && isEnabled ? 0.08 : 0)))
                .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
                .onHover { hovered = $0 }
                .animation(.easeOut(duration: 0.15), value: hovered)
                .animation(.easeOut(duration: 0.06), value: configuration.isPressed)
        }
    }
}
