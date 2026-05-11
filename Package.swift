// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "Dictator",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "Dictator", targets: ["Dictator"]),
        .library(name: "DictatorCore", targets: ["DictatorCore"])
    ],
    targets: [
        .target(name: "DictatorCore"),
        .executableTarget(
            name: "Dictator",
            dependencies: ["DictatorCore"]
        ),
        .testTarget(
            name: "DictatorCoreTests",
            dependencies: ["DictatorCore"]
        )
    ]
)
