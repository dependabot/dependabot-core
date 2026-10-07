// swift-tools-version:5.8.0
import PackageDescription

let package = Package(
    name: "MyApp",
    dependencies: [
        .package(url: "https://github.com/apple/swift-nio.git", exact: "2.54.0")
    ]
)
