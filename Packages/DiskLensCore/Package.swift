// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DiskLensCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "DiskLensCore", targets: ["DiskLensCore"]),
        .executable(name: "disklens", targets: ["disklens"]),
    ],
    targets: [
        .target(name: "DiskLensCore", resources: [.process("Rules/rules.json")]),
        .executableTarget(name: "disklens", dependencies: ["DiskLensCore"]),
        .testTarget(name: "DiskLensCoreTests", dependencies: ["DiskLensCore"]),
    ]
)
