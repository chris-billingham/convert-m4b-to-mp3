// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "M4BtoMP3",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "M4BtoMP3",
            path: "Sources/M4BtoMP3"
        )
    ]
)
