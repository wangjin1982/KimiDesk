// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "KimiDesk",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "KimiDesk",
            path: "Sources/KimiDesk"
        )
    ]
)
