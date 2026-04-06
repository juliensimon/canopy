// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Tempo",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", from: "1.2.0"),
    ],
    targets: [
        .executableTarget(
            name: "Tempo",
            dependencies: ["SwiftTerm"],
            path: "Tempo",
            exclude: ["App/Tempo.entitlements"],
            swiftSettings: [
                .swiftLanguageMode(.v5),
            ]
        ),
        .testTarget(
            name: "TempoTests",
            dependencies: ["Tempo"],
            path: "Tests"
        ),
    ]
)
