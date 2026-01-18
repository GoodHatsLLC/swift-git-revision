// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
  name: "swift-git-revision",
  platforms: [
    .macOS(.v15)
  ],
  products: [
    .plugin(
      name: "GitRevisionInfo",
      targets: ["GitRevisionInfo"]
    ),
  ],
  targets: [
    .executableTarget(
      name: "Generator",
      swiftSettings: [
        .swiftLanguageMode(.v6),
        .enableUpcomingFeature("StrictConcurrency"),
      ]
    ),
    .plugin(
      name: "GitRevisionInfo",
      capability: .buildTool(),
      dependencies: [
        .target(name: "Generator")
      ]
    ),
    .testTarget(
      name: "GeneratorTests",
      dependencies: ["Generator"]
    ),
  ],
  swiftLanguageModes: [.v6]
)
