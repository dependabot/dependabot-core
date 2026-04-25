// swift-tools-version: 6.1

import PackageDescription

let package = Package(
  name: "SamplePackage",
  dependencies: [
    .package(
      url: "https://github.com/apple/swift-atomics.git",
      from: "1.2.0",
    ),
    .package(
      url: "https://github.com/apple/swift-collections.git",
      .upToNextMajor(from: "1.4.0",),
    ),
    .package(
      url: "https://github.com/apple/swift-log.git",
      .upToNextMajor(from: "1.11.0"),
    ),
    .package(
      url: "https://github.com/apple/swift-docc-plugin",
      .upToNextMinor(from: "1.4.5",),
    ),
    .package(
      url: "https://github.com/apple/swift-argument-parser",
      .upToNextMinor(from: "1.7.0"),
    ),
    .package(
      url: "https://github.com/apple/swift-nio-http2.git",
      exact: "1.42.0",
    ),
    .package(
      url: "https://github.com/apple/swift-crypto.git",
      .exact("4.3.1",),
    ),
    .package(
      url: "https://github.com/apple/swift-numerics.git",
      .exact("1.1.0"),
    ),
  ]
)
