// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "LyricalNotch", platforms: [.macOS(.v14)],
    dependencies: [.package(url: "https://github.com/jpsim/Yams.git", exact: "6.2.2")],
    targets: [.executableTarget(name: "LyricalNotch", dependencies: [.product(name: "Yams", package: "Yams")])],
    swiftLanguageModes: [.v5])
