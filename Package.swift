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
        .target(
            name: "LaunchScopePrivilegedCore",
            path: "Sources/LaunchScopePrivilegedCore",
            linkerSettings: [.linkedFramework("Security")]
        ),
        .executableTarget(
            name: "LaunchScopePrivilegedHelper",
            dependencies: ["LaunchScopePrivilegedProtocol", "LaunchScopePrivilegedCore"],
            path: "Sources/LaunchScopePrivilegedHelper"
        ),
        .testTarget(
            name: "LaunchScopeTests",
            dependencies: ["LaunchScope", "LaunchScopePrivilegedProtocol", "LaunchScopePrivilegedCore"],
            path: "Tests/LaunchScopeTests",
            resources: [.copy("Fixtures")]
        ),
    ],
    swiftLanguageModes: [.v5]
)
