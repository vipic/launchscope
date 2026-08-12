// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "LaunchScope",
    platforms: [.macOS("26.0")],
    products: [
        .executable(name: "LaunchScope", targets: ["LaunchScope"]),
        .executable(name: "LaunchScopePrivilegedHelper", targets: ["LaunchScopePrivilegedHelper"]),
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "LaunchScope",
            dependencies: ["LaunchScopePrivilegedProtocol"],
            path: "Sources/LaunchScope",
            resources: [.process("Resources")],
            linkerSettings: [.linkedFramework("Security"), .linkedFramework("UserNotifications")]
        ),
        .target(
            name: "LaunchScopePrivilegedProtocol",
            path: "Sources/LaunchScopePrivilegedProtocol"
        ),
        .executableTarget(
            name: "LaunchScopePrivilegedHelper",
            dependencies: ["LaunchScopePrivilegedProtocol"],
            path: "Sources/LaunchScopePrivilegedHelper"
        ),
        .testTarget(
            name: "LaunchScopeTests",
            dependencies: ["LaunchScope", "LaunchScopePrivilegedProtocol"],
            path: "Tests/LaunchScopeTests",
            resources: [.copy("Fixtures")]
        ),
    ],
    swiftLanguageModes: [.v5]
)
