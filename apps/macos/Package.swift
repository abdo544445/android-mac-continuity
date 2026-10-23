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
            name: "ContinuityProtocol",
            dependencies: [],
            path: "Sources/ContinuityProtocol"
        ),
        .executableTarget(
            name: "ContinuityCompanion",
            dependencies: ["ContinuityProtocol"],
            path: "Sources/ContinuityCompanion"
        ),
        .executableTarget(
            name: "ContinuityCLI",
            dependencies: ["ContinuityProtocol"],
            path: "Sources/ContinuityCLI"
        )
    ]
)
