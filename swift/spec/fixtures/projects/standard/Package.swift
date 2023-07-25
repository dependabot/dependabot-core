// swift-tools-version:5.8.0

import PackageDescription

let package = Package(
    name: "tuist",
    dependencies: [
        .package(url: "https://github.com/apple/swift-nio-http2.git", exact: "1.19.2")
    ]
)
