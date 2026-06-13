// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "swift-webapp-frameworkless",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.77.0"),
        .package(url: "https://github.com/apple/swift-nio-ssl.git", from: "2.29.0"),
    ],
    targets: [
        .executableTarget(
            name: "Application",
            dependencies: [
                .product(name: "NIO", package: "swift-nio"),
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
                .product(name: "NIOHTTP1", package: "swift-nio"),
                .product(name: "NIOSSL", package: "swift-nio-ssl"),
            ],
            path: "Sources/Application"
        ),
//        .testTarget(
//            name: "AppTests",
//            dependencies: ["App"],
//            path: "Tests/AppTests"
//        ),
    ]
)
