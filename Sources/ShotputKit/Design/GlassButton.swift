import AppKit

extension NSButton {
    /// A native round glass button with one symbol, as used over thumbnails. Hover, press,
    /// focus, and the circle itself all come from AppKit.
    static func glassCircle(_ icon: Icon, label: String, target: AnyObject?, action: Selector) -> NSButton {
        let button = NSButton(image: icon.plain(label: label), target: target, action: action)
        button.bezelStyle = .glass
        button.borderShape = .circle
        button.controlSize = .regular
        button.translatesAutoresizingMaskIntoConstraints = false
        button.toolTip = label
        button.setAccessibilityLabel(label)
        return button
    }

    /// Shows a check in place of the icon for a moment, so the action visibly landed.
    func confirm(restoring icon: Icon) {
        let label = accessibilityLabel()
        image = Icon.checkmark.plain(label: label)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { [weak self] in self?.image = icon.plain(label: label) }
    }
}
