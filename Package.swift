// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "LaunchScope",
    platforms: [.macOS("26.0")],
    products: [
        .executable(name: "LaunchScope", targets: ["LaunchScope"]),
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "LaunchScope",
            path: "Sources/LaunchScope",
            resources: [.process("Resources")],
            linkerSettings: [.linkedFramework("Security"), .linkedFramework("UserNotifications")]
        ),
        .testTarget(
            name: "LaunchScopeTests",
            dependencies: ["LaunchScope"],
            path: "Tests/LaunchScopeTests",
            resources: [.copy("Fixtures")]
        ),
    ],
    swiftLanguageModes: [.v5]
)
