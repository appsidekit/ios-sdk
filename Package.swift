// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SideKit",
    platforms: [
        .iOS(.v15),
        .macOS(.v15)
    ],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "SideKit",
            targets: ["SideKit"]
        ),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "SideKit",
            path: "Sources/SideKit"
        ),
        .testTarget(
            name: "SideKitTests",
            dependencies: ["SideKit"],
            path: "Tests/SideKitTests"
        ),
    ]
)
