// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "HermesViz",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "HermesViz", targets: ["HermesViz"])],
    dependencies: [
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.0.0"),
        .package(url: "https://github.com/apple/swift-markdown.git", branch: "main"),
    ],
    targets: [
        .executableTarget(
            name: "HermesViz",
            dependencies: ["Yams", .product(name: "Markdown", package: "swift-markdown")],
            path: "Sources",
            resources: [
                .copy("Services/hermes_chat_bridge.py"),
            ]
        )
    ]
)
