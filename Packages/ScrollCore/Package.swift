// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ScrollCore",
    platforms: [.iOS(.v17), .watchOS(.v10), .macOS(.v13)],
    products: [.library(name: "ScrollCore", targets: ["ScrollCore"])],
    targets: [
        .target(name: "ScrollCore"),
        .testTarget(name: "ScrollCoreTests", dependencies: ["ScrollCore"]),
    ]
)
