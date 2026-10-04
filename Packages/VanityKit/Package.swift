// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "VanityKit",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "VanityKit", targets: ["VanityKit"]),
    ],
    targets: [
        .target(name: "VanityKit"),
        .testTarget(name: "VanityKitTests", dependencies: ["VanityKit"]),
    ]
)
