// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "cdesk",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "CDesk", targets: ["CDesk"]),
        .executable(name: "cdesk-mcp", targets: ["cdesk-mcp"]),
        .library(name: "ColimaKit", targets: ["ColimaKit"]),
    ],
    targets: [
        // UI-free core: runs the colima / docker CLIs and parses their output.
        .target(name: "ColimaKit"),
        // The menu bar + Dock app.
        .executableTarget(name: "CDesk", dependencies: ["ColimaKit"]),
        // Model Context Protocol server (stdio) so agents can drive Colima.
        .executableTarget(name: "cdesk-mcp", dependencies: ["ColimaKit"]),
        .testTarget(name: "ColimaKitTests", dependencies: ["ColimaKit"]),
    ],
    swiftLanguageModes: [.v5]
)
