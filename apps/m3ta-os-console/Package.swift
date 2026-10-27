// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "M3taOSConsole",
    platforms: [.macOS(.v26)],
    products: [.executable(name: "M3taOSConsole", targets: ["M3taOSConsole"])],
    targets: [
        .target(name: "ConsoleCore", resources: [.copy("Resources/mesh-state-2026-10-26.json"), .copy("Resources/bot-map-20261027.json")]),
        .executableTarget(name: "M3taOSConsole", dependencies: ["ConsoleCore"]),
        .testTarget(name: "ConsoleCoreTests", dependencies: ["ConsoleCore"]),
    ]
)
