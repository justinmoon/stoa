// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Stoa",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "stoa", targets: ["Stoa"]),
    ],
    targets: [
        // Main Stoa application
        .executableTarget(
            name: "Stoa",
            dependencies: ["StoaKit"],
            path: "Sources/Stoa",
            swiftSettings: [
                .unsafeFlags(["-import-objc-header", "Sources/Stoa/BridgingHeader.h"])
            ],
            linkerSettings: [
                .linkedFramework("Cocoa"),
                .linkedFramework("Metal"),
                .linkedFramework("QuartzCore"),
                .linkedFramework("IOSurface"),
                .linkedFramework("Carbon"),
                .linkedFramework("UniformTypeIdentifiers"),
                .unsafeFlags([
                    "-I", "Libraries/GhosttyKit.xcframework/macos-arm64_x86_64/Headers",
                    "Libraries/GhosttyKit.xcframework/macos-arm64_x86_64/libghostty.a",
                    "-lc++",
                ])
            ]
        ),
        
        // Core library
        .target(
            name: "StoaKit",
            path: "Sources/StoaKit"
        ),
        
        .testTarget(
            name: "StoaTests",
            dependencies: ["StoaKit"],
            path: "Tests/StoaTests"
        ),
    ]
)
