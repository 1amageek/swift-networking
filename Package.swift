// swift-tools-version: 6.4

import PackageDescription

let ownershipSettings: [SwiftSetting] = [
    .enableExperimentalFeature("NonescapableTypes"),
    .enableExperimentalFeature("LifetimeDependence"),
    .enableExperimentalFeature("InoutLifetimeDependence"),
    .enableExperimentalFeature("LifetimeDependenceMutableAccessors"),
    .enableExperimentalFeature("Lifetimes"),
    .enableExperimentalFeature("Extern"),
]

let package = Package(
    name: "swift-networking",
    platforms: [
        .macOS(.v26),
        .iOS(.v26),
    ],
    products: [
        .library(name: "NetworkingCore", targets: ["NetworkingCore"]),
        .library(name: "NetworkingTime", targets: ["NetworkingTime"]),
        .library(name: "NetworkingDatagram", targets: ["NetworkingDatagram"]),
        .library(name: "NetworkingPOSIX", targets: ["NetworkingPOSIX"]),
        .library(name: "NetworkingWASI", targets: ["NetworkingWASI"]),
        .library(
            name: "NetworkingFoundationCompat",
            targets: ["NetworkingFoundationCompat"]
        ),
        .library(name: "TLSTypes", targets: ["TLSTypes"]),
    ],
    targets: [
        .target(
            name: "NetworkingCore",
            swiftSettings: ownershipSettings
        ),
        .target(
            name: "NetworkingTime",
            swiftSettings: ownershipSettings
        ),
        .target(
            name: "NetworkingDatagram",
            dependencies: ["NetworkingCore"],
            swiftSettings: ownershipSettings
        ),
        .target(
            name: "NetworkingPOSIX",
            dependencies: ["NetworkingCore", "NetworkingTime", "NetworkingDatagram"],
            swiftSettings: ownershipSettings
        ),
        .target(
            name: "NetworkingWASI",
            dependencies: ["NetworkingTime"],
            swiftSettings: ownershipSettings
        ),
        .target(
            name: "NetworkingFoundationCompat",
            dependencies: ["NetworkingCore", "NetworkingTime"],
            swiftSettings: ownershipSettings
        ),
        .target(
            name: "TLSTypes",
            dependencies: ["NetworkingCore"],
            swiftSettings: ownershipSettings
        ),
        .testTarget(
            name: "NetworkingCoreTests",
            dependencies: ["NetworkingCore"],
            swiftSettings: ownershipSettings
        ),
        .testTarget(
            name: "NetworkingTimeTests",
            dependencies: ["NetworkingTime"],
            swiftSettings: ownershipSettings
        ),
        .testTarget(
            name: "NetworkingDatagramTests",
            dependencies: ["NetworkingCore", "NetworkingDatagram"],
            swiftSettings: ownershipSettings
        ),
        .testTarget(
            name: "NetworkingPOSIXTests",
            dependencies: ["NetworkingCore", "NetworkingDatagram", "NetworkingPOSIX"],
            swiftSettings: ownershipSettings
        ),
        .testTarget(
            name: "NetworkingFoundationCompatTests",
            dependencies: ["NetworkingCore", "NetworkingTime", "NetworkingFoundationCompat"],
            swiftSettings: ownershipSettings
        ),
        .testTarget(
            name: "TLSTypesTests",
            dependencies: ["TLSTypes"],
            swiftSettings: ownershipSettings
        ),
    ]
)
