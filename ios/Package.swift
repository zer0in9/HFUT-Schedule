// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "HFUTSchedule",
    platforms: [.iOS("26.0")],
    products: [.library(name: "HFUTSchedule", targets: ["HFUTSchedule"])],
    dependencies: [.package(path: "Core")],
    targets: [.target(name: "HFUTSchedule", dependencies: [.product(name: "HFUTCore", package: "Core")])],
    swiftLanguageModes: [.v5]
)
