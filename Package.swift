// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "YTClipperGUI",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "YTClipperGUI", targets: ["YTClipperGUI"])],
    targets: [
        .target(name: "ClipperCore"),
        .executableTarget(name: "YTClipperGUI", dependencies: ["ClipperCore"]),
        .testTarget(name: "ClipperCoreTests", dependencies: ["ClipperCore"])
    ],
    swiftLanguageModes: [.v6]
)
