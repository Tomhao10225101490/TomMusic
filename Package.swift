// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TomMusic",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "TomMusic", targets: ["TomMusic"])],
    targets: [.executableTarget(name: "TomMusic", path: "Sources/TomMusic")]
)
