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
    // Core library with reusable log collection and analysis logic
    .target(
      name: "HomeDiagnosticsCore",
      dependencies: [
        .product(name: "Subprocess", package: "swift-subprocess")
      ]
    ),

    // Command-line executable
    .executableTarget(
      name: "HomeDiagnostics",
      dependencies: [
        "HomeDiagnosticsCore",
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
      ],
      path: "Sources/HomeDiagnostics"
    ),

    // Unit tests
    .testTarget(
      name: "HomeDiagnosticsTests",
      dependencies: [
        "HomeDiagnosticsCore"
      ],
      resources: [
        .copy("Resources/sample_logs.json")
      ]
    ),
  ]
)
