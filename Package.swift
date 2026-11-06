// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FanBar",
    platforms: [.macOS(.v11)],
    products: [
        .executable(name: "FanBar", targets: ["FanBar"]),
        .executable(name: "FanBarHelper", targets: ["FanBarHelper"]),
        .executable(name: "FanBarDiagnostics", targets: ["FanBarDiagnostics"]),
        // Shipped as FanBar.app/Contents/Helpers/fanbar. The product keeps a
        // distinct name: `fanbar` and `FanBar` collide on case-insensitive volumes.
        .executable(name: "FanBarCLI", targets: ["FanBarCLI"])
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
        .target(
            name: "FanBarUI",
            dependencies: ["FanBarShared"],
            path: "Sources/FanBarUI"
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
                "FanBarUI",
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "Sources/FanBar",
            resources: [.process("Resources")]
        ),
        .executableTarget(name: "FanBarDiagnostics", dependencies: ["FanBarShared"], path: "Sources/FanBarDiagnostics"),
        .executableTarget(name: "FanBarCLI", dependencies: ["FanBarShared"], path: "Sources/FanBarCLI"),
        .executableTarget(
            name: "FanBarWidget",
            dependencies: ["FanBarShared", "FanBarUI"],
            path: "Sources/FanBarWidget"
        ),
        .testTarget(
            name: "FanBarHelperTests",
            dependencies: ["FanBarHelper", "AppleSMC", "FanBarShared"],
            path: "Tests/FanBarHelperTests"
        ),
        .testTarget(
            name: "FanBarCLITests",
            dependencies: ["FanBarCLI", "FanBarShared"],
            path: "Tests/FanBarCLITests"
        ),
        .testTarget(
            name: "FanBarTests",
            dependencies: ["FanBar", "FanBarShared"],
            path: "Tests/FanBarTests"
        )
    ]
)
