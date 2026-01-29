// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
  name: "HomeDiagnostics",
  platforms: [
    .macOS(.v15)
  ],
  dependencies: [
    .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0"),
    .package(url: "https://github.com/swiftlang/swift-subprocess.git", from: "0.0.1"),
  ],
  targets: [
    .executableTarget(
      name: "home-diagnostics",
      dependencies: [
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
        .product(name: "Subprocess", package: "swift-subprocess"),
      ]
    ),
    .testTarget(
      name: "HomeDiagnosticsTests",
      dependencies: [
        "home-diagnostics"
      ],
      resources: [
        .copy("Resources/sample_logs.json")
      ]
    ),
  ]
)
