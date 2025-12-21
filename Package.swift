// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Stoa",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "stoa-demo-1", targets: ["Demo1"]),
    ],
    targets: [
        // Demo 1: Single Terminal Window
        .executableTarget(
            name: "Demo1",
            dependencies: ["StoaKit"],
            path: "Sources/Demo1",
            swiftSettings: [
                .unsafeFlags(["-import-objc-header", "Sources/Demo1/BridgingHeader.h"])
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
