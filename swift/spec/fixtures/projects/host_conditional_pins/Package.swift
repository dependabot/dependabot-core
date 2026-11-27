// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "App",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "App", targets: ["App"]),
    ],
    dependencies: [
        .package(path: "Packages/HostConditional"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.14.0"),
    ],
    targets: [
        .target(
            name: "App",
            dependencies: [
                "HostConditional",
                .product(name: "Logging", package: "swift-log"),
            ]
        ),
    ]
)
