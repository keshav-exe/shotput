import SwiftUI

/// The selected tool's controls, inline in the toolbar after the tools: colour, size, and the
/// options that tool has. With a mark selected they show, and change, that mark's style.
struct StyleControls: View {
    @ObservedObject var model: EditorModel

    private var tool: Tool { model.styleTool }
    private var style: MarkStyle { model.style }

    var body: some View {
        HStack(spacing: 2) {
            if tool == .redact { redactMode }
            if showsColor { ColorWell(model: model) }
            switch tool {
            case .redact where style.redaction != .blackout:
                slider(L("Strength"), value: \.size, range: 3 ... 32, coalesce: "strength")
            case .spotlight:
                slider(L("Dim"), value: \.opacity, range: 0.15 ... 0.85, coalesce: "dim")
            default:
                if !tool.sizeKind.presets.isEmpty { sizeMenu }
            }
            switch tool {
            case .rectangle, .filledRectangle, .ellipse, .spotlight: shapeMenu
            case .arrow: arrowMenu
            case .line: lineMenu
            case .text: fontMenu; textStyleMenu
            case .counter: counterMenu
            default: EmptyView()
            }
            if ![.select, .redact, .spotlight].contains(tool) { optionsMenu }
        }
        .fixedSize()
        .animation(.snappy(duration: 0.18), value: tool)
    }

    private var showsColor: Bool {
        tool.supportsColor && !(tool == .redact && style.redaction != .blackout)
    }

    private func binding<T>(_ path: WritableKeyPath<MarkStyle, T>, coalesce: String? = nil) -> Binding<T> {
        Binding(get: { model.style[keyPath: path] }, set: { value in model.setStyle(coalesce: coalesce) { $0[keyPath: path] = value } })
    }

    // MARK: Size

    private var sizeMenu: some View {
        let kind = tool.sizeKind
        return Menu {
            Picker(sizeTitle, selection: binding(\.size)) {
                ForEach(kind.presets, id: \.self) { size in
                    Text(String(format: L("%d pt"), Int(size))).tag(size)
                }
                if !kind.presets.contains(style.size) {
                    Text(String(format: L("%d pt"), Int(style.size.rounded()))).tag(style.size)
                }
            }
            .pickerStyle(.inline)
        } label: {
            HStack(spacing: 5) {
                if kind == .stroke {
                    Capsule().frame(width: 12, height: min(max(style.size * 0.55, 1.5), 6))
                }
                Text(String(format: L("%d pt"), Int(style.size.rounded()))).monospacedDigit()
            }
        }
        .toolbarMenu()
        .help(sizeTitle)
    }

    private var sizeTitle: String {
        switch tool.sizeKind {
        case .font: L("Font size")
        case .counter: L("Size")
        default: L("Line width")
        }
    }

    private func slider(_ label: String, value: WritableKeyPath<MarkStyle, CGFloat>, range: ClosedRange<CGFloat>, coalesce: String) -> some View {
        Slider(value: binding(value, coalesce: coalesce), in: range)
            .controlSize(.small)
            .frame(width: 96)
            .padding(.horizontal, 6)
            .help(label)
            .accessibilityLabel(label)
    }

    // MARK: Per-tool menus

    private var redactMode: some View {
        Menu {
            Picker(L("Redact"), selection: binding(\.redaction)) {
                ForEach(RedactMode.allCases, id: \.self) { mode in
                    Label(mode.title, systemImage: mode.icon.rawValue).tag(mode)
                }
            }
            .pickerStyle(.inline)
        } label: {
            style.redaction.icon.view(size: 13)
        }
        .toolbarMenu()
        .help(style.redaction.title)
    }

    private var shapeMenu: some View {
        Menu {
            if tool != .spotlight {
                Picker(L("Fill"), selection: binding(\.fill)) {
                    ForEach(ShapeFill.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.inline)
            }
            if tool != .ellipse {
                Picker(L("Corners"), selection: binding(\.cornerRadius)) {
                    Text(L("Square corners")).tag(CGFloat(0))
                    Text(L("Slightly rounded")).tag(CGFloat(4))
                    Text(L("Rounded corners")).tag(CGFloat(8))
                    Text(L("Very rounded")).tag(CGFloat(16))
                }
                .pickerStyle(.inline)
            }
        } label: {
            (style.fill == .outline ? Icon.unfilled : style.fill == .solid ? Icon.fill : Icon.tinted).view(size: 13)
        }
        .toolbarMenu()
        .help(L("Shape style"))
    }

    private var arrowMenu: some View {
        Menu {
            Picker(L("Arrow"), selection: binding(\.arrow)) {
                ForEach(ArrowStyle.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.inline)
            Toggle(L("Curved"), isOn: binding(\.curved))
            Picker(L("Head"), selection: binding(\.head)) {
                ForEach(HeadSize.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.inline)
        } label: {
            (style.curved ? Icon.curvedArrow : style.arrow == .double ? Icon.doubleArrow : Icon.arrow).view(size: 13)
        }
        .toolbarMenu()
        .help(L("Arrow style"))
    }

    private var lineMenu: some View {
        Menu {
            Toggle(L("Curved"), isOn: binding(\.curved))
        } label: {
            (style.curved ? Icon.curve : Icon.line).view(size: 13)
        }
        .toolbarMenu()
        .help(L("Line style"))
    }

    private var fontMenu: some View {
        Menu {
            Picker(L("Font"), selection: binding(\.font)) {
                ForEach(TextFont.allCases, id: \.self) { font in
                    Text(font.title).font(Font(TextMetrics.font({ var s = style; s.font = font; s.size = 13; return s }())))
                        .tag(font)
                }
            }
            .pickerStyle(.inline)
            Toggle(L("Bold"), isOn: binding(\.bold))
        } label: {
            Text("Aa").font(Font(TextMetrics.font({ var s = style; s.size = 13; return s }())))
        }
        .toolbarMenu()
        .help(L("Font"))
    }

    private var textStyleMenu: some View {
        Menu {
            Picker(L("Text style"), selection: binding(\.text)) {
                ForEach(TextStyle.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.inline)
        } label: {
            (style.text == .pill ? Icon.textLabel : style.text == .outlined ? Icon.textOutlined : Icon.text).view(size: 13)
        }
        .toolbarMenu()
        .help(L("Text style"))
    }

    private var counterMenu: some View {
        Menu {
            Picker(L("Step number"), selection: binding(\.counter)) {
                ForEach(CounterStyle.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.inline)
        } label: {
            (style.counter == .ring ? Icon.counter : style.counter == .square ? Icon.counterSquare : Icon.counterFilled).view(size: 13)
        }
        .toolbarMenu()
        .help(L("Step number style"))
    }

    private var optionsMenu: some View {
        Menu {
            Toggle(L("Shadow"), isOn: binding(\.shadow))
            if [.rectangle, .ellipse, .line, .pen].contains(tool) || (tool == .arrow && style.arrow != .tapered) {
                Toggle(L("Dashed"), isOn: binding(\.dashed))
            }
            Picker(L("Opacity"), selection: binding(\.opacity)) {
                ForEach([1, 0.75, 0.5, 0.25] as [CGFloat], id: \.self) { value in
                    Text(String(format: L("%d%% opacity"), Int(value * 100))).tag(value)
                }
            }
            .pickerStyle(.inline)
        } label: {
            Icon.options.view(size: 13)
        }
        .toolbarMenu()
        .help(L("More options"))
    }
}

extension RedactMode {
    var icon: Icon {
        switch self {
        case .pixelate: .redact
        case .blurSecure: .blurSecure
        case .blurSmooth: .blurSmooth
        case .blackout: .blackout
        }
    }
}

/// The current colour, with a chevron. Opens the palette.
private struct ColorWell: View {
    @ObservedObject var model: EditorModel
    @State private var open = false

    var body: some View {
        Button { open.toggle() } label: {
            HStack(spacing: 3) {
                Circle()
                    .fill(Color(nsColor: model.style.color.nsColor))
                    .overlay(Circle().strokeBorder(Color.primary.opacity(0.2), lineWidth: 0.5))
                    .frame(width: 16, height: 16)
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 6)
            .frame(height: 24)
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help(String(format: L("Colour: %@"), model.style.color.name))
        .accessibilityLabel(L("Colour"))
        .popover(isPresented: $open, arrowEdge: .bottom) {
            Swatches(model: model)
        }
    }

    private struct Swatches: View {
        @ObservedObject var model: EditorModel

        var body: some View {
            VStack(alignment: .leading, spacing: 10) {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(26), spacing: 6), count: 5), spacing: 6) {
                    ForEach(Array(Ink.palette.enumerated()), id: \.offset) { index, ink in
                        Button { model.setColor(ink) } label: {
                            ZStack {
                                Circle().strokeBorder(Color.primary, lineWidth: 2).opacity(model.style.color == ink ? 1 : 0)
                                Circle()
                                    .fill(Color(nsColor: ink.nsColor))
                                    .overlay(Circle().strokeBorder(Color.primary.opacity(0.18), lineWidth: 0.5))
                                    .padding(4)
                            }
                            .frame(width: 26, height: 26)
                            .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .help("\(ink.name)  \((index + 1) % 10)")
                        .accessibilityLabel(ink.name)
                    }
                }
                Divider()
                ColorPicker(L("Custom colour…"), selection: Binding(
                    get: { Color(nsColor: model.style.color.nsColor) },
                    set: { model.setColor(Ink(NSColor($0)), coalesce: "picker") }
                ), supportsOpacity: false)
                .font(.callout)
            }
            .padding(12)
        }
    }
}

/// The crop mode's controls: the box's shape and size, turn and flip, and the size to save at.
struct CropControls: View {
    @ObservedObject var model: EditorModel

    private var state: CropState { model.crop ?? CropState(rect: .zero) }

    var body: some View {
        HStack(spacing: 8) {
            Menu {
                Picker(L("Aspect ratio"), selection: Binding(get: { state.aspect }, set: { model.setCropAspect($0) })) {
                    ForEach(AspectRatio.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.inline)
            } label: {
                Text(state.aspect.title).frame(minWidth: 70, alignment: .leading)
            }
            .toolbarMenu()
            .help(L("Aspect ratio"))

            HStack(spacing: 4) {
                pixelField(Int((state.rect.width * model.scale).rounded())) { model.setCropPixelSize(width: CGFloat($0), height: nil) }
                    .help(L("Width in pixels"))
                Image(systemName: "arrow.left.and.right").font(.system(size: 9)).foregroundStyle(.secondary)
                pixelField(Int((state.rect.height * model.scale).rounded())) { model.setCropPixelSize(width: nil, height: CGFloat($0)) }
                    .help(L("Height in pixels"))
            }

            Divider().frame(height: 16)

            Menu {
                Button(L("Rotate left")) { model.rotate(clockwise: false) }
                Button(L("Rotate right")) { model.rotate(clockwise: true) }
            } label: {
                Icon.rotateLeft.view(size: 13)
            }
            .toolbarMenu()
            .help(L("Rotate"))
            Button { model.flip(horizontally: true) } label: { Icon.flipHorizontal.view(size: 13).frame(width: 24, height: 24) }
                .buttonStyle(.borderless)
                .help(L("Flip horizontally"))
            Button { model.flip(horizontally: false) } label: { Icon.flipVertical.view(size: 13).frame(width: 24, height: 24) }
                .buttonStyle(.borderless)
                .help(L("Flip vertically"))

            Divider().frame(height: 16)

            Text(L("Image size:")).foregroundStyle(.secondary)
            Menu {
                Picker(L("Image size"), selection: Binding(get: { state.outputScale }, set: { model.crop?.outputScale = $0 })) {
                    ForEach([1, 0.75, 0.5, 0.25] as [CGFloat], id: \.self) { scale in
                        Text("\(Int(scale * 100))%  ·  \(pixelLabel(scale))").tag(scale)
                    }
                }
                .pickerStyle(.inline)
            } label: {
                Text(pixelLabel(state.outputScale)).monospacedDigit()
            }
            .toolbarMenu()
            .help(L("The size the cropped image is saved at"))
        }
        .fixedSize()
    }

    private func pixelLabel(_ scale: CGFloat) -> String {
        let w = Int((state.rect.width * model.scale * scale).rounded())
        let h = Int((state.rect.height * model.scale * scale).rounded())
        return String(format: L("%d × %d px"), w, h)
    }

    private func pixelField(_ value: Int, commit: @escaping (Int) -> Void) -> some View {
        TextField("", value: Binding(get: { value }, set: { if $0 > 0 { commit($0) } }), format: .number.grouping(.never))
            .textFieldStyle(.roundedBorder)
            .multilineTextAlignment(.center)
            .monospacedDigit()
            .frame(width: 58)
    }
}

private extension View {
    /// A menu that sits in the toolbar like its buttons: no border, a small chevron.
    func toolbarMenu() -> some View {
        menuStyle(.button)
            .buttonStyle(.borderless)
            .menuIndicator(.visible)
            .fixedSize()
            .padding(.horizontal, 2)
            .frame(height: 24)
    }
}
