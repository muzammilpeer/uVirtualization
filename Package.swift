// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "uVirtualization",
    platforms: [.macOS(.v13)],
    products: [.library(name: "UVCore", targets: ["UVCore"]), .executable(name: "uvm", targets: ["uvm"]), .executable(name: "uVirtualization", targets: ["UVApp"]), .executable(name: "gitlab-uvm-executor", targets: ["GitLabExecutor"])],
    targets: [.target(name: "UVCore"), .executableTarget(name: "uvm", dependencies: ["UVCore"]),
              .executableTarget(name: "UVApp", dependencies: ["UVCore"]),
              .target(name: "UVGitLab", dependencies: ["UVCore"]),
              .executableTarget(name: "GitLabExecutor", dependencies: ["UVGitLab", "UVCore"]),
              .testTarget(name: "UVCoreTests", dependencies: ["UVCore", "UVGitLab"])]
)
