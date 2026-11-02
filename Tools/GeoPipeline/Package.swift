// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GeoPipeline",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "GeoPipeline"),
    ]
)
