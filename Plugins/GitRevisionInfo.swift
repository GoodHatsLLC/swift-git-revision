// © GoodHatsLLC

import Foundation
import PackagePlugin

/// Walks up from `start` until a `.git/HEAD` file is found, or returns nil.
private func findGitHead(startingFrom start: URL) -> URL? {
  var current = start
  for _ in 0..<8 {
    let candidate = current.appending(path: ".git").appending(path: "HEAD")
    if FileManager.default.fileExists(atPath: candidate.path) {
      return candidate
    }
    let parent = current.deletingLastPathComponent()
    if parent.path == current.path { break }
    current = parent
  }
  return nil
}

@main
struct GitRevisionInfo: BuildToolPlugin {
  func createBuildCommands(
    context: PluginContext,
    target: Target,
  ) throws -> [Command] {
    guard target is SourceModuleTarget else { return [] }

    let generatorTool = try context.tool(named: "Generator")
    let outputFile = context.pluginWorkDirectoryURL
      .appending(path: target.name)
      .appending(path: "Resources")
      .appending(path: "git-revision-info.json")
    let swiftOutputFile = context.pluginWorkDirectoryURL
      .appending(path: target.name)
      .appending(path: "Sources")
      .appending(path: "GitRevInfo.generated.swift")
    let repositoryPath = target.directoryURL.path
    let inputFiles = findGitHead(startingFrom: context.package.directoryURL).map { [$0] } ?? []

    return [
      .buildCommand(
        displayName: "Preparing Git revision info for \(target.name)",
        executable: generatorTool.url,
        arguments: [repositoryPath, outputFile.path, swiftOutputFile.path],
        inputFiles: inputFiles,
        outputFiles: [outputFile, swiftOutputFile],
      )
    ]
  }
}

#if canImport(XcodeProjectPlugin)
  import XcodeProjectPlugin

  extension GitRevisionInfo: XcodeBuildToolPlugin {
    func createBuildCommands(context: XcodePluginContext, target: XcodeTarget) throws -> [Command] {
      let generatorTool = try context.tool(named: "Generator")
      let outputFile = context.pluginWorkDirectoryURL
        .appending(path: target.displayName)
        .appending(path: "Resources")
        .appending(path: "git-revision-info.json")
      let swiftOutputFile = context.pluginWorkDirectoryURL
        .appending(path: target.displayName)
        .appending(path: "Sources")
        .appending(path: "GitRevInfo.generated.swift")
      let repositoryPath = context.xcodeProject.directoryURL.path
      let inputFiles =
        findGitHead(startingFrom: context.xcodeProject.directoryURL).map { [$0] } ?? []

      return [
        .buildCommand(
          displayName: "Preparing Git revision info for \(target.displayName)",
          executable: generatorTool.url,
          arguments: [repositoryPath, outputFile.path, swiftOutputFile.path],
          inputFiles: inputFiles,
          outputFiles: [outputFile, swiftOutputFile],
        )
      ]
    }
  }
#endif
