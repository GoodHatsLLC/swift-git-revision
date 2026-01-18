import Foundation
import PackagePlugin

@main
struct GitRevisionInfo: BuildToolPlugin {
  func createBuildCommands(
    context: PluginContext,
    target: Target
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

    return [
      .buildCommand(
        displayName: "Preparing Git revision info for \(target.name)",
        executable: generatorTool.url,
        arguments: [repositoryPath, outputFile.path, swiftOutputFile.path],
        inputFiles: [],
        outputFiles: [outputFile, swiftOutputFile]
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

      return [
        .buildCommand(
          displayName: "Preparing Git revision info for \(target.displayName)",
          executable: generatorTool.url,
          arguments: [repositoryPath, outputFile.path, swiftOutputFile.path],
          inputFiles: [],
          outputFiles: [outputFile, swiftOutputFile]
        )
      ]
    }
  }
#endif
