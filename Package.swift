// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Aether",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Aether", targets: ["Aether"])
    ],
    dependencies: [
        .package(
            url: "https://github.com/moreaki/aether-zydis.git",
            revision: "7ef9c6674e7ce39ce41c283e54f16cacb44b3af4"
        ),
        .package(url: "https://github.com/appstefan/highlightswift.git", exact: "1.0.5")
    ],
    targets: [
        .executableTarget(
            name: "Aether",
            dependencies: [
                .product(name: "CZydis", package: "aether-zydis"),
                .product(name: "HighlightSwift", package: "highlightswift")
            ],
            path: "Sources/Aether",
            resources: [
                .process("Resources")
            ]
        )
    ]
)
