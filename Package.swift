// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AirPoise",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "AirPoiseCore", targets: ["AirPoiseCore"]),
        .executable(name: "AirPoise", targets: ["AirPoise"])
    ],
    targets: [
        .target(
            name: "AirPoiseCore",
            path: "Sources/AirPoiseCore",
            linkerSettings: [
                .linkedFramework("CoreMotion")
            ]
        ),
        .executableTarget(
            name: "AirPoise",
            dependencies: ["AirPoiseCore"],
            path: "Sources/AirPoise",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("CoreMotion"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("UserNotifications"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("SceneKit"),
                .linkedFramework("Carbon"),
                .linkedFramework("ApplicationServices")
            ]
        ),
        .testTarget(
            name: "AirPoiseTests",
            dependencies: ["AirPoiseCore"],
            path: "Tests/AirPoiseTests"
        )
    ]
)
