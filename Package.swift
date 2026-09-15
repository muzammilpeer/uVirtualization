// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "uVirtualization",
    platforms: [.macOS(.v13)],
    products: [.library(name: "UVCore", targets: ["UVCore"]), .executable(name: "uvm", targets: ["uvm"])],
    targets: [.target(name: "UVCore"), .executableTarget(name: "uvm", dependencies: ["UVCore"]),
              .testTarget(name: "UVCoreTests", dependencies: ["UVCore"])]
)
