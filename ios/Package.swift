// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "HFUTSchedule",
    platforms: [.iOS("26.0")],
    products: [.library(name: "HFUTSchedule", targets: ["HFUTSchedule"])],
    dependencies: [.package(path: "Packages/HFUTCore")],
    targets: [
        .target(
            name: "HFUTSchedule",
            dependencies: [.product(name: "HFUTCore", package: "HFUTCore")],
            path: "HFUTSchedule",
            exclude: ["Info.plist", "Resources"]
        )
    ],
    swiftLanguageModes: [.v5]
)
