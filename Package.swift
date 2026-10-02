// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "DockLayout",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "docklayout", targets: ["docklayout"]),
        .executable(name: "DockLayoutApp", targets: ["DockLayoutApp"]),
    ],
    targets: [
        .target(name: "DockLayoutCore"),
        .executableTarget(name: "docklayout", dependencies: ["DockLayoutCore"]),
        .executableTarget(name: "DockLayoutApp", dependencies: ["DockLayoutCore"]),
        // Run with `swift run DockLayoutChecks`; see the file for why it isn't a test target.
        .executableTarget(name: "DockLayoutChecks", dependencies: ["DockLayoutCore"], path: "Tests/DockLayoutChecks"),
    ]
)
