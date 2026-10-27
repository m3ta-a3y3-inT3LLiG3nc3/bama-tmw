// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "M3taTasks",
    platforms: [.macOS(.v26)],
    targets: [
        // Rules and data logic with no SwiftUI, so tests run without the app.
        .target(name: "M3taTasksKit"),
        .executableTarget(
            name: "M3taTasks",
            dependencies: ["M3taTasksKit"],
            // App code runs on the main thread unless you say otherwise.
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .testTarget(name: "M3taTasksKitTests", dependencies: ["M3taTasksKit"]),
    ]
)
