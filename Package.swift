// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "QuickMD",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "QuickMD",
            path: "Sources/QuickMD",
            swiftSettings: [.swiftLanguageMode(.v5), .enableUpcomingFeature("BareSlashRegexLiterals")]
        ),
        .testTarget(
            name: "QuickMDTests",
            dependencies: ["QuickMD"],
            path: "Tests/QuickMDTests",
            swiftSettings: [.swiftLanguageMode(.v5), .enableUpcomingFeature("BareSlashRegexLiterals")]
        ),
    ]
)
