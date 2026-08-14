// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "DshMacLauncher",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "DshLauncherCore", targets: ["DshLauncherCore"]),
        .executable(name: "DshMacLauncher", targets: ["DshMacLauncher"]),
    ],
    targets: [
        .target(name: "DshLauncherCore"),
        .executableTarget(
            name: "DshMacLauncher",
            dependencies: ["DshLauncherCore"]
        ),
        .executableTarget(
            name: "DshLauncherSmokeChecks",
            dependencies: ["DshLauncherCore"],
            path: "SmokeChecks"
        ),
        .testTarget(
            name: "DshLauncherCoreTests",
            dependencies: ["DshLauncherCore"]
        ),
    ]
)
