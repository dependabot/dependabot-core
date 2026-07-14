// swift-tools-version:5.8.0

import PackageDescription

let package = Package(
    name: "MyPackage",
    dependencies: [
        .package(url: "https://github.com/Quick/Quick", .revision("2ce7e2373106b1b562dc965e1eee2324f9e72e3"))
    ]
)
