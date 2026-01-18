# swift-git-revision

Capture your build time git revision details for runtime use and display.   
A Swift Package Manager plugin.

## Swift Package Manager

### 1) Add the plugin to your `Package.swift`.

Add the package to your `Package.swift` dependencies and the plugin to your target.

```swift
// swift-tools-version: 6.2
import PackageDescription

let package = Package(
  name: "SomePackage",
  products: .library(
    name: "MyLibrary",
    targets: ["MyTarget"]
  ),
  dependencies: [
    .package(url: "https://github.com/username/swift-git-revision.git", from: "0.1.0")
  ],
  targets: [
    .executableTarget(
      name: "MyTarget",
      plugins: [
        .plugin(name: "GitRevisionInfo", package: "swift-git-revision")
      ]
    )
  ]
)
```

### 2) Load the info with `GitRevInfo.current`

The plugin generates a public `GitRevInfo` type inside the target that uses the bundle where the JSON
was generated.

```swift
let info = try GitRevInfo.current
print(info.hash)
```

## Xcode Project

### 1) Add the package dependency

In Xcode:

1. File > Add Packages...
2. Enter the package URL and add it to your project.

### 2) Enable the build tool plugin

In the target's settings:

1. Select your target.
2. Build Phases > Run Build Tool Plug-ins.
3. Click `+` and add `GitRevisionInfo`.

This plugin runs on every build, generates `git-revision-info.json`, and adds a generated `GitRevInfo` type
to the target so you can load without passing bundles manually.

### 3) Load the revision at runtime

```swift
let info = try GitRevInfo.current
print(info.shortHash)
```

## Notes

- The plugin reads from the repository containing the target being built.
- If the repository has no commits or is not a Git repository, the plugin fails the build with a descriptive error.
- The JSON file uses ISO 8601 timestamps; if you generate the file yourself, use the same format or decoding will fail.
- If `git` is not in `PATH`, set `SWIFT_GIT_REVISION_GIT_PATH` to the full path of the executable.
- The plugin generates a `GitRevInfo` type per target; for shared access across modules, enable the plugin in a shared module.
