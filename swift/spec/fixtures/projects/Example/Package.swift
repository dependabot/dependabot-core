// swift-tools-version:5.6
import PackageDescription

let package = Package(
  name: "Example",
  dependencies: [
    .package(url: "https://github.com/ReactiveCocoa/ReactiveSwift.git",
             exact: "7.1.0"),

    .package(
      url: "https://github.com/apple/swift-docc-plugin",
      from: "1.0.0"),

    .package(url: "https://github.com/google/swift-benchmark", "0.1.0"..<"0.1.2"),
    .package(url: "https://github.com/pointfreeco/combine-schedulers", "0.9.2"..."0.10.0"),

    .package(url: "https://github.com/pointfreeco/swift-case-paths",
             branch: "main"),

    .package(url: "https://github.com:443/pointfreeco/swift-custom-dump",
               revision: "3a35f7892e7cf6ba28a78cd46a703c0be4e0c6dc")
  ]
)
