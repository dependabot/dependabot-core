// swift-tools-version: 5.8
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "swift-package-monitored-by-dependabot",
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "swift-package-monitored-by-dependabot",
            targets: ["swift-package-monitored-by-dependabot"]),
    ],
    dependencies: [.package(url:  "https://github.com/MarcoEidinger/DummySwiftPackage.git", from: "1.0.0"),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "swift-package-monitored-by-dependabot",
            dependencies: [.product(name: "DummySwiftPackage", package: "DummySwiftPackage")]
        )
    ]
)
