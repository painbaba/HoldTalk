// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "HoldTalk",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "HoldTalkKit"),
        .executableTarget(name: "HoldTalk", dependencies: ["HoldTalkKit"]),
        .testTarget(name: "HoldTalkKitTests", dependencies: ["HoldTalkKit"]),
    ]
)
