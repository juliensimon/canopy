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
            // CLAUDE.md files are claude-mem plugin markers (git-ignored,
            // also excluded in project.yml for the Xcode build).
            // Assets.xcassets is consumed by the Xcode app build, not SPM.
            exclude: ["App/Canopy.entitlements", "Assets.xcassets", "Models/CLAUDE.md", "Views/CLAUDE.md", "Services/CLAUDE.md"],
            swiftSettings: [
                .swiftLanguageMode(.v5),
            ]
        ),
        .testTarget(
            name: "CanopyTests",
            dependencies: ["Canopy"],
            path: "Tests",
            exclude: ["CLAUDE.md"]
        ),
    ]
)
