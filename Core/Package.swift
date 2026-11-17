// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "LumbergCore",
    platforms: [.macOS(.v14)],
    products: [.library(name: "LumbergCore", targets: ["LumbergCore"])],
    targets: [
        .target(name: "LumbergCore"),
        .executableTarget(name: "lumberg-ascii", dependencies: ["LumbergCore"]),
        .testTarget(name: "LumbergCoreTests", dependencies: ["LumbergCore"]),
    ]
)
