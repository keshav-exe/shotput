import AppKit
import SwiftUI

/// Shotput lives in the menu bar. While an editor or the settings window is open it joins the
/// Dock and the app switcher, so those windows are easy to get back to.
final class AppPresence {
    static let shared = AppPresence()
    private var openWindows = 0

    func windowDidOpen() {
        openWindows += 1
        if openWindows == 1 { NSApp.setActivationPolicy(.regular) }
    }

    func windowDidClose() {
        openWindows = max(0, openWindows - 1)
        DispatchQueue.main.async { [self] in
            if openWindows == 0 { NSApp.setActivationPolicy(.accessory) }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate {
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Output.purgeTemporaryFiles()
        NSApp.mainMenu = MainMenu.build()

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "viewfinder", accessibilityDescription: "Shotput")
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item

        HotKeyCenter.reload()
        if Settings.shared.consumeFirstLaunch() { showSettings(nil) }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows { showSettings(nil) }
        return true
    }

    // MARK: Opening files and links

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            if url.isFileURL {
                CaptureCoordinator.shared.open(file: url)
            } else if url.scheme == "shotput" {
                handle(command: url.host ?? "")
            }
        }
    }

    /// `shotput://` links let launchers and Logi Options+ Smart Actions start a capture. Only
    /// commands that put interactive UI on screen are exposed. A silent full-screen capture is
    /// not, because any app can open a link and could use that to read the screen.
    private func handle(command: String) {
        switch command {
        case "area": HotAction.area.perform()
        case "annotate": HotAction.areaAnnotate.perform()
        case "window": HotAction.window.perform()
        case "last": HotAction.annotateLast.perform()
        case "settings": showSettings(nil)
        default: break
        }
    }

    // MARK: Menu bar

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let shortcuts = Settings.shared.shortcuts

        func add(_ action: HotAction, _ selector: Selector) {
            let item = menu.addItem(withTitle: action.title, action: selector, keyEquivalent: "")
            item.target = self
            if let shortcut = shortcuts[action], shortcut.isSet, shortcut.keyName.count == 1 {
                item.keyEquivalent = shortcut.keyName.lowercased()
                item.keyEquivalentModifierMask = shortcut.flags
            }
        }

        add(.area, #selector(captureArea))
        add(.areaAnnotate, #selector(captureAreaAndAnnotate))
        add(.window, #selector(captureWindow))
        add(.screen, #selector(captureScreen))
        menu.addItem(.separator())
        add(.annotateLast, #selector(annotateLast))
        menu.addItem(withTitle: "Annotate clipboard image", action: #selector(annotateClipboard), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings…", action: #selector(showSettings(_:)), keyEquivalent: ",").target = self
        menu.addItem(withTitle: "Quit Shotput", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        if item.action == #selector(annotateLast) { return CaptureCoordinator.shared.lastCapture != nil }
        if item.action == #selector(annotateClipboard) { return NSPasteboard.general.canReadObject(forClasses: [NSImage.self]) }
        return true
    }

    @objc private func captureArea() { HotAction.area.perform() }
    @objc private func captureAreaAndAnnotate() { HotAction.areaAnnotate.perform() }
    @objc private func captureWindow() { HotAction.window.perform() }
    @objc private func captureScreen() { HotAction.screen.perform() }
    @objc private func annotateLast() { HotAction.annotateLast.perform() }
    @objc private func annotateClipboard() { CaptureCoordinator.shared.annotateClipboard() }

    // MARK: Settings

    @objc func showSettings(_ sender: Any?) {
        if settingsWindow == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView()))
            window.title = "Shotput Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            settingsWindow = window
        }
        if settingsWindow?.isVisible == false { AppPresence.shared.windowDidOpen() }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        if notification.object as? NSWindow === settingsWindow { AppPresence.shared.windowDidClose() }
    }
}

enum MainMenu {
    /// Shown while a Shotput window is open. Items with no target travel the responder chain, which
    /// is how ⌘C reaches the editor and text fields alike.
    static func build() -> NSMenu {
        let main = NSMenu()

        func submenu(_ title: String, _ build: (NSMenu) -> Void) {
            let item = NSMenuItem()
            let menu = NSMenu(title: title)
            build(menu)
            item.submenu = menu
            main.addItem(item)
        }

        func item(_ menu: NSMenu, _ title: String, _ action: Selector, _ key: String, _ flags: NSEvent.ModifierFlags = .command) {
            menu.addItem(withTitle: title, action: action, keyEquivalent: key).keyEquivalentModifierMask = flags
        }

        submenu("Shotput") { menu in
            item(menu, "About Shotput", #selector(NSApplication.orderFrontStandardAboutPanel(_:)), "")
            menu.addItem(.separator())
            item(menu, "Settings…", #selector(AppDelegate.showSettings(_:)), ",")
            menu.addItem(.separator())
            item(menu, "Hide Shotput", #selector(NSApplication.hide(_:)), "h")
            item(menu, "Quit Shotput", #selector(NSApplication.terminate(_:)), "q")
        }
        submenu("File") { menu in
            item(menu, "Save…", #selector(EditorWindowController.saveDocument(_:)), "s")
            item(menu, "Close", #selector(NSWindow.performClose(_:)), "w")
        }
        submenu("Edit") { menu in
            item(menu, "Undo", #selector(CanvasView.undo(_:)), "z")
            item(menu, "Redo", #selector(CanvasView.redo(_:)), "z", [.command, .shift])
            menu.addItem(.separator())
            item(menu, "Cut", #selector(NSText.cut(_:)), "x")
            item(menu, "Copy", #selector(NSText.copy(_:)), "c")
            item(menu, "Paste", #selector(NSText.paste(_:)), "v")
            item(menu, "Delete", #selector(NSText.delete(_:)), "")
            item(menu, "Select All", #selector(NSText.selectAll(_:)), "a")
        }
        submenu("View") { menu in
            item(menu, "Zoom In", #selector(EditorWindowController.zoomImageIn(_:)), "+")
            item(menu, "Zoom Out", #selector(EditorWindowController.zoomImageOut(_:)), "-")
            item(menu, "Actual Size", #selector(EditorWindowController.zoomImageToActualSize(_:)), "0")
            item(menu, "Zoom to Fit", #selector(EditorWindowController.zoomImageToFit(_:)), "9")
        }
        submenu("Window") { menu in
            item(menu, "Minimize", #selector(NSWindow.performMiniaturize(_:)), "m")
            NSApp.windowsMenu = menu
        }
        return main
    }
}
