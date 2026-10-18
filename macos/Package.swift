// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "OnePlusConnect",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "OnePlusConnect",
            path: "Sources/OnePlusConnect"
        ),
        .testTarget(
            name: "OnePlusConnectTests",
            dependencies: ["OnePlusConnect"],
            path: "Tests/OnePlusConnectTests"
        )
    ]
)
