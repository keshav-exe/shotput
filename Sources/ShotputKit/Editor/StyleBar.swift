import SwiftUI

/// The floating bar under the image, with a toast slot above it. Undo, redo, and the actions for
/// the finished image while marking up; edge snapping and Revert to Original while cropping.
/// Colour, size, and the rest of a tool's style live in the toolbar.
struct EditorBar: View {
    struct Actions {
        let copyText: () -> Void
        let float: () -> Void
        let pin: () -> Void
        let save: () -> Void
    }

    @ObservedObject var model: EditorModel
    let actions: Actions
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
                if model.crop != nil {
                    Toggle(isOn: $model.snapsToEdges) {
                        Text(L("Snap to edges")).foregroundStyle(Palette.ink.color)
                    }
                    .toggleStyle(.checkbox)
                    .help(L("Hold ⌘ while dragging to switch snapping for that drag"))
                    Text(L("Hold ⌘ to switch"))
                        .font(.caption)
                        .foregroundStyle(Palette.ink.color.opacity(0.55))
                    divider
                    Button(L("Revert to Original")) { model.revertToOriginal() }
                        .buttonStyle(.borderless)
                        .disabled(!model.canRevert)
                } else {
                    BarButton(icon: .undo, label: L("Undo"), isSelected: false) { model.undo() }
                        .disabled(!model.canUndo)
                        .opacity(model.canUndo ? 1 : 0.35)
                    BarButton(icon: .redo, label: L("Redo"), isSelected: false) { model.redo() }
                        .disabled(!model.canRedo)
                        .opacity(model.canRedo ? 1 : 0.35)
                    divider
                    BarButton(icon: .readText, label: L("Copy text: reads the text in this screenshot and copies it"), isSelected: false, action: actions.copyText)
                    BarButton(icon: .float, label: L("Float on screen: keeps this screenshot above every window"), isSelected: false, action: actions.float)
                    BarButton(icon: .pin, label: L("Pin to the menu bar"), isSelected: false, action: actions.pin)
                    BarButton(icon: .save, label: L("Save  ⌘S"), isSelected: false, action: actions.save)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .fixedSize()
            .frame(minHeight: 42)
            .glassEffect(.regular, in: .capsule)
        }
        .padding(Metrics.spacingS)
        .animation(.snappy(duration: 0.25), value: model.toast)
        .animation(.snappy(duration: 0.2), value: model.crop == nil)
    }

    private var divider: some View {
        Rectangle()
            .fill(Palette.ink.color.opacity(0.12))
            .frame(width: 1, height: 18)
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

/// The bar's hover and press, matching the toolbar's buttons: a faint circle on hover, a
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
