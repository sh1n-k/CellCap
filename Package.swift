// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CellCap",
    platforms: [
        .macOS("26.0")
    ],
    products: [
        .library(name: "Shared", targets: ["Shared"]),
        .library(name: "Core", targets: ["Core"]),
        .executable(name: "CellCapApp", targets: ["AppUI"]),
        .executable(name: "CellCapHelper", targets: ["Helper"])
    ],
    targets: [
        .target(
            name: "CellCapSMCBridge",
            path: "Sources/CellCapSMCBridge",
            publicHeadersPath: "include",
            linkerSettings: [
                .linkedFramework("CoreFoundation"),
                .linkedFramework("IOKit")
            ]
        ),
        .target(
            name: "Shared"
        ),
        .target(
            name: "Core",
            dependencies: ["Shared"]
        ),
        .executableTarget(
            name: "AppUI",
            dependencies: ["Core", "Shared"]
        ),
        .executableTarget(
            name: "Helper",
            dependencies: ["CellCapSMCBridge", "Core", "Shared"]
        ),
        .testTarget(
            name: "CoreTests",
            dependencies: ["Core", "Shared", "Helper"]
        )
    ]
)
