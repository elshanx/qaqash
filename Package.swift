// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Qaqash",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(name: "Qaqash", exclude: ["Info.plist"], swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "QaqashTests", dependencies: ["Qaqash"], swiftSettings: [.swiftLanguageMode(.v5)]),
    ]
)
