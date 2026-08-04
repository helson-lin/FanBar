// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FanBar",
    platforms: [.macOS(.v11)],
    products: [
        .executable(name: "FanBar", targets: ["FanBar"]),
        .executable(name: "FanBarHelper", targets: ["FanBarHelper"])
    ],
    targets: [
        .target(
            name: "AppleSMC",
            path: "Sources/AppleSMC",
            publicHeadersPath: "include",
            linkerSettings: [.linkedFramework("IOKit")]
        ),
        .target(
            name: "FanBarShared",
            path: "Sources/FanBarShared"
        ),
        .executableTarget(
            name: "FanBarHelper",
            dependencies: ["AppleSMC", "FanBarShared"],
            path: "Sources/FanBarHelper"
        ),
        .executableTarget(
            name: "FanBar",
            dependencies: ["AppleSMC", "FanBarShared"],
            path: "Sources/FanBar"
        )
    ]
)
