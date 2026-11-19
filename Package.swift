// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "DMXStudio",
    platforms: [.macOS(.v12)],   // macOS Monterey and newer
    targets: [
        .executableTarget(name: "DMXStudio", path: "Sources/DMXStudio")
    ]
)
