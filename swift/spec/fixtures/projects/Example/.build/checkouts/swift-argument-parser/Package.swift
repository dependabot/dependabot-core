// swift-tools-version:5.2
//===----------------------------------------------------------*- swift -*-===//
//
// This source file is part of the Swift Argument Parser open source project
//
// Copyright (c) 2020 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
//
//===----------------------------------------------------------------------===//

import PackageDescription

var package = Package(
    name: "swift-argument-parser",
    products: [
        .library(
            name: "ArgumentParser",
            targets: ["ArgumentParser"]),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "ArgumentParser",
            dependencies: ["ArgumentParserToolInfo"]),
        .target(
            name: "ArgumentParserToolInfo",
            dependencies: [])
    ]
)
