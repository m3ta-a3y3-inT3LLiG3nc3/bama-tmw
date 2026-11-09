// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "M3taOSConsole",
    platforms: [.macOS(.v26), .iOS(.v26)],
    products: [
        .library(name: "ConsoleCore", targets: ["ConsoleCore"]),
        .executable(name: "M3taOSConsole", targets: ["M3taOSConsole"]),
        .executable(name: "M3taOSConsoleMobile", targets: ["M3taOSConsoleMobile"]),
        .executable(name: "ConsoleCoreService", targets: ["ConsoleCoreService"]),
    ],
    targets: [
        .target(name: "ConsoleCore", resources: [.copy("Resources/mesh-state-2026-10-26.json"), .copy("Resources/bot-map-20261027.json"), .copy("Resources/dashboard-state-2026-11-02.json")]),
        .executableTarget(name: "M3taOSConsole", dependencies: ["ConsoleCore"]),
        .executableTarget(name: "M3taOSConsoleMobile", dependencies: ["ConsoleCore"], path: "Sources/M3taOSConsoleMobile"),
        .executableTarget(name: "ConsoleCoreService", dependencies: ["ConsoleCore"]),
        .testTarget(name: "ConsoleCoreTests", dependencies: ["ConsoleCore"]),
    ]
)
