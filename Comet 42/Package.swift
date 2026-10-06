// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Comet",
    platforms: [.macOS("26.0")],
    targets: [
        .executableTarget(
            name: "Comet",
            path: "Sources/Comet",
            swiftSettings: [.defaultIsolation(MainActor.self)]
        )
    ]
)
