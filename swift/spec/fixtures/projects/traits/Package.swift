// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "traits",
    dependencies: [
        .package(url: "https://github.com/ordo-one/benchmark", from: "1.30.0", traits: []),
    ],
    targets: []
)
