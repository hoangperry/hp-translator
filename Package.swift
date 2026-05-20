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
    dependencies: [
        // Sparkle 2 — auto-update framework. SPM binary target ships
        // Sparkle.framework + XPC services as an XCFramework. The
        // `package_app.sh` script copies the framework + XPCServices
        // into `.app/Contents/Frameworks/` and code-signs them.
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.2")
    ],
    targets: [
        .executableTarget(
            name: "ContextualMacTranslator",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "Sources/ContextualMacTranslator",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "ContextualMacTranslatorTests",
            dependencies: ["ContextualMacTranslator"],
            path: "Tests/ContextualMacTranslatorTests",
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
