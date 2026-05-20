// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "ContextualMacTranslator",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "ContextualMacTranslator",
            targets: ["ContextualMacTranslator"]
        )
    ],
    targets: [
        .executableTarget(
            name: "ContextualMacTranslator",
            path: "Sources/ContextualMacTranslator"
        ),
        .testTarget(
            name: "ContextualMacTranslatorTests",
            dependencies: ["ContextualMacTranslator"],
            path: "Tests/ContextualMacTranslatorTests"
        )
    ]
)
