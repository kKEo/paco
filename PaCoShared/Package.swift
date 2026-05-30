// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PaCoShared",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "PaCoShared", targets: ["PaCoShared"]),
    ],
    targets: [
        .target(name: "PaCoShared"),
        // .testTarget(name: "PaCoSharedTests", dependencies: ["PaCoShared"]),
    ]
)
