// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ClassPlannerCore",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "ClassPlannerCore", targets: ["ClassPlannerCore"])
    ],
    targets: [
        .target(name: "ClassPlannerCore"),
        .testTarget(name: "ClassPlannerCoreTests", dependencies: ["ClassPlannerCore"])
    ]
)
