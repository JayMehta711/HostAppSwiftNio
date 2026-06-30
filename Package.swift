// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "HostAppSwiftNio",
    platforms: [
        .iOS(.v15),
        .macOS(.v14)
    ],
    products: [
        .executable(name: "HostAppSwiftNio", targets: ["HostAppSwiftNio"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.56.0")
    ],
    targets: [
        .executableTarget(
            name: "HostAppSwiftNio",
            dependencies: [
                .product(name: "NIO", package: "swift-nio"),
                .product(name: "NIOHTTP1", package: "swift-nio"),
                .product(name: "NIOFoundationCompat", package: "swift-nio")
            ],
            path: "HostAppSwiftNio",
            resources: [
                .copy("Resources/index.html"),
                .process("Assets.xcassets")
            ]
        )
    ]
)
