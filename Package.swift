// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "CPAQuotaBar",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(
            name: "CPAQuotaBar",
            targets: ["CPAQuotaBar"]
        ),
    ],
    targets: [
        .executableTarget(
            name: "CPAQuotaBar",
            path: "Sources/CPAQuotaBar"
        ),
        .testTarget(
            name: "CPAQuotaBarTests",
            dependencies: ["CPAQuotaBar"],
            path: "Tests/CPAQuotaBarTests"
        ),
    ]
)
