// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Dictado",
    platforms: [.macOS("26.0")],
    targets: [
        .executableTarget(
            name: "Dictado",
            path: "Sources/Dictado",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
