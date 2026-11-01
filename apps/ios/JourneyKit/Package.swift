// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "JourneyKit",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "JourneyKit", targets: ["JourneyKit"]),
        .executable(name: "journey", targets: ["journey"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift", from: "7.11.1")
    ],
    targets: [
        .target(
            name: "JourneyKit",
            dependencies: [.product(name: "GRDB", package: "GRDB.swift")]
        ),
        .executableTarget(name: "journey", dependencies: ["JourneyKit"]),
        .testTarget(
            name: "JourneyKitTests",
            dependencies: ["JourneyKit"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
