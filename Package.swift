// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FanBar",
    platforms: [.macOS(.v11)],
    products: [
        .executable(name: "FanBar", targets: ["FanBar"]),
        .executable(name: "FanBarHelper", targets: ["FanBarHelper"])
    ],
    dependencies: [
        // Pin release tooling and the embedded updater to the same audited build.
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.9.6")
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
            dependencies: [
                "AppleSMC",
                "FanBarShared",
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "Sources/FanBar"
        ),
        .testTarget(
            name: "FanBarTests",
            dependencies: ["FanBar", "FanBarShared"],
            path: "Tests/FanBarTests"
        )
    ]
)
