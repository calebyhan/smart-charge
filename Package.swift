// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "BatterySmartCharge",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "BatterySmartCharge", targets: ["BatterySmartCharge"])
    ],
    targets: [
        .target(
            name: "SMCBridge",
            path: "SMCBridge",
            publicHeadersPath: "include"
        ),
        .executableTarget(
            name: "BatterySmartCharge",
            dependencies: ["SMCBridge"],
            path: "BatterySmartCharge",
            resources: [
                .process("Assets.xcassets")
            ]
        )
    ]
)
