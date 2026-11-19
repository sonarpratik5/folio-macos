// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "FolioMac",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "FolioMac", targets: ["FolioMac"])],
    targets: [
        .target(name: "FolioCore"),
        .executableTarget(name: "FolioMac", dependencies: ["FolioCore"], resources: [.copy("Resources/Math")]),
        .executableTarget(name: "FolioPaperTools", dependencies: ["FolioCore"]),
        .testTarget(name: "FolioCoreTests", dependencies: ["FolioCore"]),
        .testTarget(name: "FolioMacTests", dependencies: ["FolioMac"])
    ]
)
