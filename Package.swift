// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "ServerApp",
    platforms: [
        // Ensure availability of modern Swift Regex and strict concurrency features
        .macOS(.v14)
    ],
    products: [
        .executable(name: "ServerApp", targets: ["ServerApp"])
    ],
    dependencies: [
        // The single Apple-backed dependency for core network streaming
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.65.0")
    ],
    targets: [
        .executableTarget(
            name: "ServerApp",
            dependencies: [
                // Pull in SwiftNIO and its specific HTTP parsing module
                .product(name: "NIO", package: "swift-nio"),
                .product(name: "NIOHTTP1", package: "swift-nio")
            ],
            path: "Sources"
        )
    ]
)
