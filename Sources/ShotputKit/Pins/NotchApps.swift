import AppKit

/// Other apps that live in the notch. Ours share it with Shotput; anyone else's are named in the
/// guide, so you can pick whether pins go to the notch or the menu bar icon.
@MainActor
enum NotchApps {
    struct App: Equatable {
        let name: String
        let bundleIDs: [String]
    }

    /// Ours. They hear when Shotput takes the notch for a drag and step back until it's done.
    static let companions = [
        App(name: "Clove", bundleIDs: ["com.kshvbgde.clove"]),
    ]

    /// Notch apps from other developers, by bundle id and by the name their app is installed as.
    static let others = [
        App(name: "NotchNook", bundleIDs: ["lo.cafe.NotchNook"]),
        App(name: "Boring Notch", bundleIDs: ["theboringteam.boringnotch"]),
        App(name: "Alcove", bundleIDs: ["com.henrikruscon.Alcove"]),
        App(name: "NotchDrop", bundleIDs: ["com.lakr233.NotchDrop", "wiki.qaq.NotchDrop"]),
        App(name: "DynamicLake", bundleIDs: ["com.aviorrok.DynamicLakePro"]),
        App(name: "MediaMate", bundleIDs: ["com.tweaking-apps.MediaMate"]),
        App(name: "Atoll", bundleIDs: ["com.ebullioscopic.Atoll"]),
        App(name: "Notchmeister", bundleIDs: ["com.iconfactory.Notchmeister"]),
    ]

    /// Development only: the notch apps to pretend are installed, for renders of the guide.
    static var assumeInstalled: [String]?

    /// The other developers' notch apps on this Mac, by name.
    static func installedOthers() -> [String] {
        assumeInstalled ?? others.filter(isInstalled).map(\.name)
    }

    static func isInstalled(_ app: App) -> Bool {
        if app.bundleIDs.contains(where: { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) != nil }) { return true }
        // Bundle ids change between releases and stores; the installed name rarely does.
        let names = Set([app.name, app.name.replacingOccurrences(of: " ", with: "")].map { $0.lowercased() })
        if NSWorkspace.shared.runningApplications.contains(where: { names.contains(($0.localizedName ?? "").replacingOccurrences(of: " ", with: "").lowercased()) }) {
            return true
        }
        let folders = ["/Applications", NSHomeDirectory() + "/Applications"]
        return folders.contains { folder in
            names.contains { FileManager.default.fileExists(atPath: "\(folder)/\($0).app") }
                || FileManager.default.fileExists(atPath: "\(folder)/\(app.name).app")
        }
    }

    // MARK: Sharing the notch

    /// Posted while Shotput's island is up, and again when it's gone. Names only: a sandboxed
    /// app can't send anything more across, and there's nothing more to say.
    static let didClaim = Notification.Name("app.shotput.notch.didClaim")
    static let didRelease = Notification.Name("app.shotput.notch.didRelease")

    private static var isClaimed = false

    /// Clove's island is open: a peek, its panel, or a moment. Shotput doesn't open over it for
    /// a drag that's going somewhere else, only for one heading for the notch.
    private(set) static var companionIsOpen = false
    static let cloveDidOpen = Notification.Name("com.kshvbgde.clove.notch.didOpen")
    static let cloveDidClose = Notification.Name("com.kshvbgde.clove.notch.didClose")

    /// Clove is wearing ears of its own beside the closed notch (a timer, music, a call). Shotput
    /// then can't wear its ears too, so its pins step out into a small bubble past Clove's right
    /// ear, the way iOS shows a second live activity beside the island.
    private(set) static var companionShowsEars = false
    static let cloveEarsDidShow = Notification.Name("com.kshvbgde.clove.notch.earsDidShow")
    static let cloveEarsDidHide = Notification.Name("com.kshvbgde.clove.notch.earsDidHide")
    /// How far Clove's ears reach past each side of the notch, shoulder included. Shared by
    /// agreement, since a sandboxed app can't send the number across.
    static let companionEarReach: CGFloat = 46
    private static var observers: [Any] = []
    /// Clove opened, closed, launched or quit: what the notch shows at rest may change.
    static let companionDidChange = Notification.Name("ShotputNotchCompanionDidChange")

    private static var companionIDs: Set<String> { Set(companions.flatMap(\.bundleIDs)) }

    /// Clove is running, so the notch itself is its to open on hover and click. Shotput's pins
    /// wear ears beside it, or a bubble past Clove's own ears while it has them.
    static var companionIsRunning: Bool {
        let ids = companionIDs
        return NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier.map(ids.contains) ?? false }
    }

    private static func changed() {
        NotificationCenter.default.post(name: companionDidChange, object: nil)
    }

    /// Starts hearing when Clove opens and closes. A Clove that quits while open counts as closed.
    static func listen() {
        guard observers.isEmpty else { return }
        let center = DistributedNotificationCenter.default()
        observers.append(center.addObserver(forName: cloveDidOpen, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                companionIsOpen = true
                changed()
            }
        })
        observers.append(center.addObserver(forName: cloveDidClose, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                companionIsOpen = false
                changed()
            }
        })
        for (name, showing) in [(cloveEarsDidShow, true), (cloveEarsDidHide, false)] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated {
                    companionShowsEars = showing
                    changed()
                }
            })
        }
        let ids = companionIDs
        for name in [NSWorkspace.didTerminateApplicationNotification, NSWorkspace.didLaunchApplicationNotification] {
            observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { note in
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                let quit = name == NSWorkspace.didTerminateApplicationNotification
                MainActor.assumeIsolated {
                    guard let id = app?.bundleIdentifier, ids.contains(id) else { return }
                    if quit {
                        companionIsOpen = false
                        companionShowsEars = false
                    }
                    changed()
                }
            })
        }
    }

    /// Asks Clove and the rest of ours to fold back to the bare notch, so the island grows out
    /// of a clean notch instead of over their ears.
    static func claim() {
        guard !isClaimed else { return }
        isClaimed = true
        DistributedNotificationCenter.default().postNotificationName(didClaim, object: nil, userInfo: nil, deliverImmediately: true)
    }

    static func release() {
        guard isClaimed else { return }
        isClaimed = false
        DistributedNotificationCenter.default().postNotificationName(didRelease, object: nil, userInfo: nil, deliverImmediately: true)
    }
}
