// swift-tools-version: 5.7
import PackageDescription

let package = Package(
    name: "EmailAgentUI",
    platforms: [
        .macOS("26.0")
    ],
    products: [
        .executable(
            name: "EmailAgentUI",
            targets: ["EmailAgentUI"]
        )
    ],
    targets: [
        .executableTarget(
            name: "EmailAgentUI",
            dependencies: [],
            path: "Sources/EmailAgentUI"
        )
    ]
)
