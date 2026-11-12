// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Shotput",
    platforms: [.macOS("26.0")],
    dependencies: [
        // Updates. The one dependency: signed appcasts, sandbox-safe installs, nothing else.
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.9.6"),
    ],
    targets: [
        .target(name: "ShotputKit", dependencies: [.product(name: "Sparkle", package: "Sparkle")], path: "Sources/ShotputKit"),
        .executableTarget(name: "Shotput", dependencies: ["ShotputKit"], path: "Sources/Shotput"),
        // Development only. Renders annotation samples and the app icon. Never bundled.
        .executableTarget(name: "shotput-dev", dependencies: ["ShotputKit"], path: "Sources/shotput-dev"),
    ],
    swiftLanguageModes: [.v5]
)
