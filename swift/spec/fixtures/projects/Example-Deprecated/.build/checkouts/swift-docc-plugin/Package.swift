// swift-tools-version:5.6
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2022 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for Swift project authors

import PackageDescription

let package = Package(
    name: "SwiftDocCPlugin",
    platforms: [
        .macOS("10.15.4"),
    ],
    targets: [
        .target(name: "SwiftDocCPluginUtilities")
    ]
)
