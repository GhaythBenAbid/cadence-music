// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "CadenceCore",
    platforms: [.macOS(.v13), .iOS(.v18), .watchOS(.v10)],
    products: [.library(name: "CadenceCore", targets: ["CadenceCore"]), .executable(name: "CadenceProbe", targets: ["CadenceProbe"])],
    targets: [.target(name: "CadenceCore"), .executableTarget(name: "CadenceProbe", dependencies: ["CadenceCore"]), .testTarget(name: "CadenceCoreTests", dependencies: ["CadenceCore"])],
    swiftLanguageModes: [.v5]
)
