// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MobileAnalytics",
    platforms: [
        .iOS(.v16),
    ],
    products: [
        .library(
            name: "MobileAnalytics",
            targets: ["MobileAnalytics"]
        ),
    ],
    targets: [
        .target(
            name: "MobileAnalytics"
        ),
    ]
)
