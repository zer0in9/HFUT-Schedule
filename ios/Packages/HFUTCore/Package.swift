// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "HFUTCore",
    platforms: [.iOS("26.0"), .macOS(.v14)],
    products: [.library(name: "HFUTCore", targets: ["HFUTCore"])],
    dependencies: [.package(url: "https://github.com/scinfu/SwiftSoup.git", exact: "2.8.8")],
    targets: [
        .target(name: "HFUTCore", dependencies: ["SwiftSoup"]),
        .testTarget(name: "HFUTCoreTests", dependencies: ["HFUTCore"], resources: [.copy("Fixtures")])
    ],
    swiftLanguageModes: [.v5]
)
