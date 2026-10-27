// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "M3taOSConsole",
    platforms: [.macOS(.v26)],
    targets: [
        // Rules and data logic with no SwiftUI, so tests run without the app.
        .target(name: "M3taOSConsoleKit"),
        .executableTarget(
            name: "M3taOSConsole",
            dependencies: ["M3taOSConsoleKit"],
            // App code runs on the main thread unless you say otherwise.
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .testTarget(name: "M3taOSConsoleKitTests", dependencies: ["M3taOSConsoleKit"]),
    ]
)
