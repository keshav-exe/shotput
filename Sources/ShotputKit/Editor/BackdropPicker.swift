import AppKit
import SwiftUI

/// The editor's Background popover: none, the wallpaper, or a colour, with padding.
@MainActor
final class BackdropControls: ObservableObject {
    enum Choice: String, CaseIterable, Identifiable {
        case none, wallpaper, color
        var id: String { rawValue }
        var title: String {
            switch self {
            case .none: "None"
            case .wallpaper: "Wallpaper"
            case .color: "Colour"
            }
        }
    }

    @Published var choice: Choice
    @Published var color: NSColor
    @Published var padding: Double

    /// Called with the style to apply, and whether it continues the previous change.
    var onChange: ((Backdrop.Style?, _ continuing: Bool) -> Void)?
    private var isSliding = false

    init(current: Backdrop.Style?) {
        choice = .none
        color = Settings.shared.windowBackgroundColor
        padding = Settings.shared.windowPadding
        sync(current)
    }

    /// Matches the controls to the image, for example after an undo, without applying anything.
    func sync(_ current: Backdrop.Style?) {
        let callback = onChange
        onChange = nil
        defer { onChange = callback }
        if let current { padding = Double(current.padding) }
        switch current?.fill {
        case .wallpaper: choice = .wallpaper
        case let .color(value):
            choice = .color
            color = value
        case nil: choice = .none
        }
    }

    var style: Backdrop.Style? {
        switch choice {
        case .none: nil
        case .wallpaper: Backdrop.Style(fill: .wallpaper, padding: padding)
        case .color: Backdrop.Style(fill: .color(color), padding: padding)
        }
    }

    func apply() {
        isSliding = false
        onChange?(style, false)
    }

    /// Slider moves fold into one undo step per drag.
    func paddingChanged() {
        onChange?(style, isSliding)
        isSliding = true
    }

    func endSlide() { isSliding = false }
}

struct BackdropPicker: View {
    @ObservedObject var controls: BackdropControls

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("Background", selection: $controls.choice) {
                ForEach(BackdropControls.Choice.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .onChange(of: controls.choice) { controls.apply() }

            if controls.choice == .color {
                ColorPicker("Colour", selection: Binding(
                    get: { Color(nsColor: controls.color) },
                    set: {
                        controls.color = NSColor($0)
                        controls.paddingChanged()
                    }
                ), supportsOpacity: false)
            }

            if controls.choice != .none {
                HStack(spacing: Metrics.spacingS) {
                    Text("Padding")
                    Slider(value: $controls.padding, in: 8...160, step: 4) { editing in
                        if !editing { controls.endSlide() }
                    }
                    .onChange(of: controls.padding) { controls.paddingChanged() }
                    Text("\(Int(controls.padding)) pt")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 46, alignment: .trailing)
                }
            }
        }
        .padding(Metrics.spacingM)
        .frame(width: 300)
        .animation(.snappy(duration: 0.2), value: controls.choice)
    }
}
