// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Garth",
    platforms: [.macOS(.v15), .iOS(.v17)],
    products: [
        .library(
            name: "Garth",
            targets: ["Garth"]
        ),
        .executable(
            name: "GarminCLI",
            targets: ["GarminCLI"]
        ),
    ],
    targets: [
        .target(
            name: "Garth"
        ),
        .executableTarget(
            name: "GarminCLI",
            dependencies: ["Garth"]
        ),
        .testTarget(
            name: "GarthTests",
            dependencies: ["Garth"]
        ),
    ]
)
