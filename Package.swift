// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "InstantLangSwitch",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "InstantLangSwitch"),
        .testTarget(name: "InstantLangSwitchTests", dependencies: ["InstantLangSwitch"])
    ]
)
