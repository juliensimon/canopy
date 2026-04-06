// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Canopy",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", from: "1.2.0"),
    ],
    targets: [
        .executableTarget(
            name: "Canopy",
            dependencies: ["SwiftTerm"],
            path: "Canopy",
            exclude: ["App/Canopy.entitlements"],
            swiftSettings: [
                .swiftLanguageMode(.v5),
            ]
        ),
        .testTarget(
            name: "CanopyTests",
            dependencies: ["Canopy"],
            path: "Tests"
        ),
    ]
)
