// swift-tools-version:5.3
import PackageDescription

let package = Package(
    name: "Example",
    dependencies: [
        .package(url: "https://github.com/mona/LinkedList.git",
                 from: "1.2.0"),

        .package(url: "https://github.com/mona/Queue",
                 .upToNextMajor(from: "1.1.1")),

        .package(url: "https://github.com/mona/HashMap.git",
                 .upToNextMinor(from: "0.9.0")),

        .package(url: "git@github.com:mona/Matrix.git",
                 .upToNextMinor(from: "2.0.1")),

        .package(url: "ssh://git@github.com:mona/RedBlackTree.git",
                 .upToNextMinor(from: "0.1.0")),

        .package(url: "https://github.com/mona/Heap",
                 .branch("main")),

        .package(url: "https://github.com:443/mona/Trie.git",
                 .revision("f3b37c3ccf0a1559d4097e2eeb883801c4b8f510"))
    ]
)
