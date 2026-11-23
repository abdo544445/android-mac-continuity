// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ContinuityEcosystem",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "ContinuityProtocol",
            targets: ["ContinuityProtocol"]
        ),
        .executable(
            name: "ContinuityCompanion",
            targets: ["ContinuityCompanion"]
        ),
        .executable(
            name: "ContinuityCLI",
            targets: ["ContinuityCLI"]
        )
    ],
    dependencies: [],
    targets: [
        .target(
            name: "CGVirtualDisplayBridge",
            dependencies: [],
            path: "Sources/CGVirtualDisplayBridge",
            publicHeadersPath: "include",
            linkerSettings: [
                .linkedFramework("CoreGraphics"),
                .linkedFramework("Foundation")
            ]
        ),
        .target(
            name: "ContinuityProtocol",
            dependencies: [],
            path: "Sources/ContinuityProtocol"
        ),
        .executableTarget(
            name: "ContinuityCompanion",
            dependencies: ["ContinuityProtocol", "CGVirtualDisplayBridge"],
            path: "Sources/ContinuityCompanion",
            linkerSettings: [
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("VideoToolbox"),
                .linkedFramework("CoreMedia"),
                .linkedFramework("CoreImage"),
                .linkedFramework("CoreVideo")
            ]
        ),
        .executableTarget(
            name: "ContinuityCLI",
            dependencies: ["ContinuityProtocol"],
            path: "Sources/ContinuityCLI"
        ),
        .testTarget(
            name: "ContinuityTests",
            dependencies: ["ContinuityProtocol"],
            path: "Tests/ContinuityTests"
        )
    ]
)
