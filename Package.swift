// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Shotput",
    platforms: [.macOS("26.0")],
    targets: [
        .target(name: "ShotputKit", path: "Sources/ShotputKit"),
        .executableTarget(name: "Shotput", dependencies: ["ShotputKit"], path: "Sources/Shotput"),
        // Development only. Renders annotation samples and the app icon. Never bundled.
        .executableTarget(name: "shotput-dev", dependencies: ["ShotputKit"], path: "Sources/shotput-dev"),
    ],
    swiftLanguageModes: [.v5]
)
