// swift-tools-version: 5.9
import Foundation
import PackageDescription

let packageRoot = FileManager.default.currentDirectoryPath

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
            dependencies: ["StoaCEF", "StoaKit"],
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
                    "-F", "\(packageRoot)/Libraries/CEF",
                    "-framework", "Chromium Embedded Framework",
                    "-lc++",
                ])
            ]
        ),
        
        // Core library
        .target(
            name: "StoaKit",
            path: "Sources/StoaKit"
        ),

        .target(
            name: "StoaCEF",
            path: "Sources/StoaCEF",
            publicHeadersPath: "include",
            cxxSettings: [
                .headerSearchPath("../../Libraries/CEF"),
                .unsafeFlags(["-std=c++17"])
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-F", "\(packageRoot)/Libraries/CEF",
                    "-framework", "Chromium Embedded Framework",
                    "-lc++",
                ])
            ]
        ),
        
        .testTarget(
            name: "StoaTests",
            dependencies: ["StoaKit"],
            path: "Tests/StoaTests"
        ),
    ]
)
