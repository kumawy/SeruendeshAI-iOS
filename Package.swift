// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SeruCore",
    platforms: [.macOS(.v14), .iOS(.v26)],
    products: [.library(name: "SeruCore", targets: ["SeruCore"])],
    targets: [
        .target(name: "SeruCore", path: "SeruendeshAI/Core"),
        .testTarget(name: "SeruCoreTests", dependencies: ["SeruCore"], path: "Tests")
    ]
)
