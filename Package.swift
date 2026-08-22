// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "MomentMonitor",
  platforms: [
    .macOS(.v14)
  ],
  products: [
    .library(name: "MomentMonitorCore", targets: ["MomentMonitorCore"]),
    .executable(name: "MomentMonitor", targets: ["MomentMonitor"]),
  ],
  targets: [
    .target(
      name: "MomentMonitorCore",
      resources: [.process("MobileDashboard")],
      swiftSettings: [
        .enableUpcomingFeature("StrictConcurrency")
      ]
    ),
    .executableTarget(
      name: "MomentMonitor",
      dependencies: ["MomentMonitorCore"],
      swiftSettings: [
        .enableUpcomingFeature("StrictConcurrency")
      ]
    ),
    .testTarget(
      name: "MomentMonitorCoreTests",
      dependencies: ["MomentMonitorCore"],
      resources: [.process("Fixtures")],
      swiftSettings: [
        .enableUpcomingFeature("StrictConcurrency")
      ]
    ),
  ]
)
