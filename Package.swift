// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LensCue",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "LensCue", targets: ["LensCue"])],
    targets: [
        .target(name: "CueCore"),
        .executableTarget(name: "LensCue", dependencies: ["CueCore"]),
        .testTarget(name: "CueCoreTests", dependencies: ["CueCore"])
    ],
    swiftLanguageModes: [.v5]
)
