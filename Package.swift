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
    dependencies: [
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", from: "0.9.0"),
        .package(url: "https://github.com/garmin/fit-objective-c-sdk.git", from: "21.171.0"),
    ],
    targets: [
        .target(
            name: "Garth"
        ),
        .executableTarget(
            name: "GarminCLI",
            dependencies: [
                "Garth",
                .product(name: "ZIPFoundation", package: "ZIPFoundation"),
                .product(name: "FIT", package: "fit-objective-c-sdk"),
            ]
        ),
        .testTarget(
            name: "GarthTests",
            dependencies: ["Garth"]
        ),
    ]
)
