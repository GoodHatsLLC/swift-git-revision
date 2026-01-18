import Foundation
import XCTest

@testable import Generator

final class InfoCollectorTests: XCTestCase {
  func testCollectsInfoForRepository() throws {
    let repoURL = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: repoURL) }

    let harness = try GitTestHarness()
    try harness.initializeRepository(at: repoURL)
    try harness.createCommit(in: repoURL, message: "Initial commit")

    let collector = InfoCollector(repositoryURL: repoURL)
    let info = try collector.collect()

    XCTAssertNotNil(info.branch)
    XCTAssertEqual(info.lastCommit.subject, "Initial commit")
    XCTAssertEqual(info.lastCommit.author.name, harness.authorName)
    XCTAssertEqual(info.lastCommit.author.email, harness.authorEmail)
    XCTAssertEqual(info.lastCommit.committer.name, harness.committerName)
    XCTAssertEqual(info.lastCommit.committer.email, harness.committerEmail)
    XCTAssertEqual(info.lastCommit.authorDate, harness.commitDate)
    XCTAssertEqual(info.lastCommit.commitDate, harness.commitDate)
    XCTAssertEqual(info.lastCommit.hash.count, 40)
    XCTAssertTrue(info.lastCommit.hash.hasPrefix(info.lastCommit.shortHash))
  }

  func testCollectThrowsForNonRepository() throws {
    let repoURL = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: repoURL) }

    let collector = InfoCollector(repositoryURL: repoURL)

    XCTAssertThrowsError(try collector.collect()) { error in
      guard case CollectorError.notAGitRepository = error else {
        return XCTFail("Expected notAGitRepository, got \(error)")
      }
    }
  }

  func testCollectThrowsForEmptyRepository() throws {
    let repoURL = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: repoURL) }

    let harness = try GitTestHarness()
    try harness.initializeRepository(at: repoURL)

    let collector = InfoCollector(repositoryURL: repoURL)

    XCTAssertThrowsError(try collector.collect()) { error in
      guard case CollectorError.noCommit = error else {
        return XCTFail("Expected noCommit, got \(error)")
      }
    }
  }

  func testCollectThrowsForMissingGitExecutable() throws {
    let repoURL = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: repoURL) }

    let missingGitURL = repoURL.appending(path: "missing-git")
    let collector = InfoCollector(repositoryURL: repoURL, gitURL: missingGitURL)

    XCTAssertThrowsError(try collector.collect()) { error in
      guard case CollectorError.executableNotFound = error else {
        return XCTFail("Expected executableNotFound, got \(error)")
      }
    }
  }

  func testCollectThrowsForInvalidRepositoryPath() throws {
    let repoURL = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: repoURL) }

    let fileURL = repoURL.appending(path: "not-a-directory")
    try "data".write(to: fileURL, atomically: true, encoding: .utf8)

    let collector = InfoCollector(repositoryURL: fileURL)

    XCTAssertThrowsError(try collector.collect()) { error in
      guard case CollectorError.repositoryPathInvalid = error else {
        return XCTFail("Expected repositoryPathInvalid, got \(error)")
      }
    }
  }

  func testCollectThrowsForGitNotAvailable() throws {
    let repoURL = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: repoURL) }

    let (scriptDirectory, gitURL) = try makeGitStub(
      stderr: "xcrun: error: invalid active developer path (/Library/Developer/CommandLineTools)",
      exitCode: 1
    )
    defer { try? FileManager.default.removeItem(at: scriptDirectory) }

    let collector = InfoCollector(repositoryURL: repoURL, gitURL: gitURL)

    XCTAssertThrowsError(try collector.collect()) { error in
      guard case CollectorError.gitNotAvailable = error else {
        return XCTFail("Expected gitNotAvailable, got \(error)")
      }
    }
  }

  func testCollectThrowsForUnsafeRepository() throws {
    let repoURL = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: repoURL) }

    let (scriptDirectory, gitURL) = try makeGitStub(
      stderr: "fatal: detected dubious ownership in repository at '$PWD'",
      exitCode: 128
    )
    defer { try? FileManager.default.removeItem(at: scriptDirectory) }

    let collector = InfoCollector(repositoryURL: repoURL, gitURL: gitURL)

    XCTAssertThrowsError(try collector.collect()) { error in
      guard case CollectorError.unsafeRepository = error else {
        return XCTFail("Expected unsafeRepository, got \(error)")
      }
    }
  }

  func testCollectThrowsForRepositoryPermissionDenied() throws {
    let repoURL = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: repoURL) }

    let (scriptDirectory, gitURL) = try makeGitStub(
      stderr: "fatal: unable to access '.git': Permission denied",
      exitCode: 128
    )
    defer { try? FileManager.default.removeItem(at: scriptDirectory) }

    let collector = InfoCollector(repositoryURL: repoURL, gitURL: gitURL)

    XCTAssertThrowsError(try collector.collect()) { error in
      guard case CollectorError.repositoryPermissionDenied = error else {
        return XCTFail("Expected repositoryPermissionDenied, got \(error)")
      }
    }
  }

  func testCollectThrowsForGitFailed() throws {
    let repoURL = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: repoURL) }

    let (scriptDirectory, gitURL) = try makeGitStub(
      stderr: "fatal: something went wrong",
      exitCode: 1
    )
    defer { try? FileManager.default.removeItem(at: scriptDirectory) }

    let collector = InfoCollector(repositoryURL: repoURL, gitURL: gitURL)

    XCTAssertThrowsError(try collector.collect()) { error in
      guard case CollectorError.gitFailed = error else {
        return XCTFail("Expected gitFailed, got \(error)")
      }
    }
  }

  func testCollectThrowsForUnexpectedOutput() throws {
    let repoURL = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: repoURL) }

    let (scriptDirectory, gitURL) = try makeGitStub(
      stdout: "true",
      exitCode: 0
    )
    defer { try? FileManager.default.removeItem(at: scriptDirectory) }

    let collector = InfoCollector(repositoryURL: repoURL, gitURL: gitURL)

    XCTAssertThrowsError(try collector.collect()) { error in
      guard case CollectorError.unexpectedOutput = error else {
        return XCTFail("Expected unexpectedOutput, got \(error)")
      }
    }
  }

  func testCollectsInfoForBareRepository() throws {
    let baseURL = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: baseURL) }

    let workURL = baseURL.appending(path: "work")
    let bareURL = baseURL.appending(path: "bare.git")
    try FileManager.default.createDirectory(
      at: workURL, withIntermediateDirectories: true, attributes: nil)

    let harness = try GitTestHarness()
    try harness.initializeRepository(at: workURL)
    try harness.createCommit(in: workURL, message: "Initial commit")
    try harness.cloneBare(from: workURL, to: bareURL)

    let collector = InfoCollector(repositoryURL: bareURL)
    let info = try collector.collect()

    XCTAssertEqual(info.lastCommit.subject, "Initial commit")
    XCTAssertEqual(info.branch, "main")
  }
}

private func makeTemporaryDirectory() throws -> URL {
  let url = FileManager.default.temporaryDirectory
    .appending(path: "swift-git-revision-")
    .appending(path: UUID().uuidString)
  try FileManager.default.createDirectory(
    at: url, withIntermediateDirectories: true, attributes: nil)
  return url
}

private func makeGitStub(
  stdout: String = "",
  stderr: String = "",
  exitCode: Int32
) throws -> (directory: URL, gitURL: URL) {
  let directory = try makeTemporaryDirectory()
#if os(Windows)
  let scriptURL = directory.appending(path: "git.cmd")
  let script = makeWindowsGitStub(stdout: stdout, stderr: stderr, exitCode: exitCode)
  try script.write(to: scriptURL, atomically: true, encoding: .utf8)
  return (directory, scriptURL)
#else
  let scriptURL = directory.appending(path: "git")
  let script = makeUnixGitStub(stdout: stdout, stderr: stderr, exitCode: exitCode)
  try script.write(to: scriptURL, atomically: true, encoding: .utf8)
  try FileManager.default.setAttributes(
    [.posixPermissions: 0o755],
    ofItemAtPath: scriptURL.path
  )
  return (directory, scriptURL)
#endif
}

#if os(Windows)
private func makeWindowsGitStub(stdout: String, stderr: String, exitCode: Int32) -> String {
  var script = "@echo off\n"
  script += windowsEchoLines(stdout, toStdErr: false)
  script += windowsEchoLines(stderr, toStdErr: true)
  script += "exit /b \(exitCode)\n"
  return script
}

private func windowsEchoLines(_ message: String, toStdErr: Bool) -> String {
  guard !message.isEmpty else { return "" }
  let lines = message.split(whereSeparator: \.isNewline)
  var output = ""
  for line in lines {
    let escaped = escapeForCmdEcho(String(line))
    if toStdErr {
      output += "echo \(escaped) 1>&2\n"
    } else {
      output += "echo \(escaped)\n"
    }
  }
  return output
}

private func escapeForCmdEcho(_ value: String) -> String {
  var escaped = ""
  for character in value {
    switch character {
    case "%":
      escaped.append("%%")
    case "^", "&", "|", "<", ">":
      escaped.append("^")
      escaped.append(character)
    default:
      escaped.append(character)
    }
  }
  return escaped
}
#else
private func makeUnixGitStub(stdout: String, stderr: String, exitCode: Int32) -> String {
  var script = "#!/bin/sh\n"
  if !stdout.isEmpty {
    script += "cat <<'GIT_STDOUT'\n\(stdout)\nGIT_STDOUT\n"
  }
  if !stderr.isEmpty {
    script += "cat <<'GIT_STDERR' 1>&2\n\(stderr)\nGIT_STDERR\n"
  }
  script += "exit \(exitCode)\n"
  return script
}
#endif

private struct GitTestHarness {
  let gitURL: URL
  let authorName = "Test Author"
  let authorEmail = "author@example.com"
  let committerName = "Test Committer"
  let committerEmail = "committer@example.com"
  let commitTimestamp = TimeInterval(1_700_000_000)

  init() throws {
    guard let resolved = InfoCollector.resolveGitExecutableURL(
      environment: ProcessInfo.processInfo.environment
    ) else {
      throw XCTSkip("git executable not available in PATH")
    }
    self.gitURL = resolved
  }

  var commitDate: Date {
    Date(timeIntervalSince1970: commitTimestamp)
  }

  func initializeRepository(at url: URL) throws {
    _ = try runGit(arguments: ["init"], in: url, environment: [:])
  }

  func createCommit(in url: URL, message: String) throws {
    let fileURL = url.appending(path: "README.md")
    try "Test".write(to: fileURL, atomically: true, encoding: .utf8)

    _ = try runGit(arguments: ["add", "README.md"], in: url, environment: [:])

    let commitEnvironment = [
      "GIT_AUTHOR_NAME": authorName,
      "GIT_AUTHOR_EMAIL": authorEmail,
      "GIT_COMMITTER_NAME": committerName,
      "GIT_COMMITTER_EMAIL": committerEmail,
      "GIT_AUTHOR_DATE": String(Int(commitTimestamp)),
      "GIT_COMMITTER_DATE": String(Int(commitTimestamp)),
    ]

    let commitArguments = [
      "-c", "user.name=\(committerName)",
      "-c", "user.email=\(committerEmail)",
      "-c", "commit.gpgsign=false",
      "commit", "-m", message,
    ]

    _ = try runGit(arguments: commitArguments, in: url, environment: commitEnvironment)
    _ = try runGit(arguments: ["branch", "-M", "main"], in: url, environment: [:])
  }

  func cloneBare(from source: URL, to destination: URL) throws {
    let parent = source.deletingLastPathComponent()
    _ = try runGit(
      arguments: ["clone", "--bare", source.path, destination.path],
      in: parent,
      environment: [:]
    )
  }

  @discardableResult
  private func runGit(
    arguments: [String],
    in directory: URL,
    environment: [String: String]
  ) throws -> GitResult {
    let process = Process()

    var fullEnvironment = ProcessInfo.processInfo.environment
    fullEnvironment["LC_ALL"] = "C"
    environment.forEach { key, value in
      fullEnvironment[key] = value
    }
    process.environment = fullEnvironment

#if os(Windows)
    if isCommandScript(gitURL) {
      guard let commandInterpreter = resolveCommandInterpreter(environment: fullEnvironment) else {
        throw XCTSkip("cmd.exe not available to run git script")
      }
      process.executableURL = commandInterpreter
      process.arguments = ["/C", gitURL.path] + arguments
    } else {
      process.executableURL = gitURL
      process.arguments = arguments
    }
#else
    process.executableURL = gitURL
    process.arguments = arguments
#endif
    process.currentDirectoryURL = directory

    let stdoutPipe = Pipe()
    let stderrPipe = Pipe()
    process.standardOutput = stdoutPipe
    process.standardError = stderrPipe

    try process.run()
    process.waitUntilExit()

    let stdout = String(
      decoding: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    let stderr = String(
      decoding: stderrPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    let result = GitResult(stdout: stdout, stderr: stderr, exitCode: process.terminationStatus)

    guard result.exitCode == 0 else {
      throw GitTestError(command: arguments.joined(separator: " "), result: result)
    }

    return result
  }
}

#if os(Windows)
private func isCommandScript(_ url: URL) -> Bool {
  let ext = url.pathExtension.lowercased()
  return ext == "cmd" || ext == "bat"
}

private func resolveCommandInterpreter(environment: [String: String]) -> URL? {
  if let comspec = environment["COMSPEC"], !comspec.isEmpty {
    let expanded = (comspec as NSString).expandingTildeInPath
    if expanded.contains("/") || expanded.contains("\\") {
      let url = URL(fileURLWithPath: expanded)
      if FileManager.default.fileExists(atPath: url.path) {
        return url
      }
    }
  }

  guard let pathValue = environment["PATH"], !pathValue.isEmpty else {
    return nil
  }

  let candidates = ["cmd.exe", "cmd"]
  for entry in pathValue.split(separator: ";") {
    let trimmed = String(entry).trimmingCharacters(in: .whitespacesAndNewlines)
      .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
    guard !trimmed.isEmpty else { continue }
    let baseURL = URL(fileURLWithPath: trimmed, isDirectory: true)
    for candidate in candidates {
      let url = baseURL.appendingPathComponent(candidate)
      if FileManager.default.fileExists(atPath: url.path) {
        return url
      }
    }
  }

  return nil
}
#endif

private struct GitResult {
  let stdout: String
  let stderr: String
  let exitCode: Int32
}

private struct GitTestError: LocalizedError {
  let command: String
  let result: GitResult

  var errorDescription: String? {
    let stdout = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
    var message = "git \(command) failed with exit code \(result.exitCode)"
    if !stdout.isEmpty {
      message += "\nstdout: \(stdout)"
    }
    if !stderr.isEmpty {
      message += "\nstderr: \(stderr)"
    }
    return message
  }
}
