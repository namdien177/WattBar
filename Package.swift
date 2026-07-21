// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "WattBar",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "WattBar", targets: ["WattBar"])
    ],
    targets: [
        .executableTarget(
            name: "WattBar",
            linkerSettings: [
                .linkedFramework("IOKit")
            ]
        ),
        .testTarget(
            name: "WattBarTests",
            dependencies: ["WattBar"]
        )
    ]
)
