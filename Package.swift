// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "nanomsg",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "nanomsg", path: "Sources")
    ]
)
