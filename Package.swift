// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NagaController",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "NagaController", targets: ["NagaController"]),
        .executable(name: "TapTester", targets: ["TapTester"]) 
    ],
    targets: [
        .executableTarget(
            name: "NagaController",
            path: "Sources/NagaController",
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("CoreBluetooth"),
                .linkedFramework("UserNotifications")
            ]
        ),
        .executableTarget(
            name: "TapTester",
            path: "Sources/TapTester"
        ),
        .testTarget(
            name: "NagaControllerTests",
            dependencies: ["NagaController"],
            path: "Tests/NagaControllerTests"
        )
    ]
)
