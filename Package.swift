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
                // Match the release build (project.yml sets SWIFT_STRICT_CONCURRENCY
                // = complete): make `swift build`/`swift test` enforce the same
                // data-race checks, so the TDD loop catches concurrency regressions
                // instead of only the Xcode archive doing so at bundle time.
                .enableUpcomingFeature("StrictConcurrency"),
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
