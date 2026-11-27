// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "HostConditional",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "HostConditional", targets: ["HostConditional"]),
    ],
    targets: [
        .target(name: "HostConditional"),
    ]
)

// Evaluated on the resolving host: OpenCombine is only added where Combine is missing, such as Linux.
#if !canImport(Combine)
package.dependencies += [
    .package(url: "https://github.com/OpenCombine/OpenCombine.git", from: "0.14.0"),
]
package.targets[0].dependencies += [
    .product(name: "OpenCombine", package: "OpenCombine"),
]
#endif
