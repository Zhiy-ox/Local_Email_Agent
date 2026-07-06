// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "EmailAgentUI",
    platforms: [
        .macOS(.v13)
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
