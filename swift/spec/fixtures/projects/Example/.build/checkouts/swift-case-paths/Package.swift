// swift-tools-version:5.5

import PackageDescription

let package = Package(
  name: "swift-case-paths",
  platforms: [
    .iOS(.v13),
    .macOS(.v10_15),
    .tvOS(.v13),
    .watchOS(.v6),
  ],
  products: [
    .library(
      name: "CasePaths",
      targets: ["CasePaths"]
    )
  ],
  dependencies: [
    .package(name: "Benchmark", url: "https://github.com/google/swift-benchmark", from: "0.1.0"),
    .package(url: "https://github.com/pointfreeco/xctest-dynamic-overlay", from: "0.8.0"),
  ],
  targets: [
    .target(
      name: "CasePaths",
      dependencies: [
        .product(name: "XCTestDynamicOverlay", package: "xctest-dynamic-overlay")
      ]
    )
  ]
)

#if swift(>=5.6)
  // Add the documentation compiler plugin if possible
  package.dependencies.append(
    .package(url: "https://github.com/apple/swift-docc-plugin", from: "1.0.0")
  )
#endif
