import Foundation

struct InfoCollector {
  let repositoryURL: URL
  private let gitURLOverride: URL?

  init(repositoryURL: URL, gitURL: URL? = nil) {
    self.repositoryURL = repositoryURL
    self.gitURLOverride = gitURL
  }

  func collect() throws -> GitRevInfo {
    let gitURL = try resolveGitURL()
    try validateRepository(gitURL: gitURL)
    try validateHasCommits(gitURL: gitURL)

    let commit = try loadLastCommit(gitURL: gitURL)
    let branch = try loadBranchName(gitURL: gitURL)
    return GitRevInfo(lastCommit: commit, branch: branch)
  }

  private func resolveGitURL() throws -> URL {
    let environment = ProcessInfo.processInfo.environment

    if let gitURLOverride {
      guard Self.isExecutableFile(at: gitURLOverride, environment: environment) else {
        throw CollectorError.executableNotFound(path: gitURLOverride.path)
      }
      return gitURLOverride
    }

    if let resolved = Self.resolveGitExecutableURL(environment: environment) {
      return resolved
    }

    throw CollectorError.executableNotFound(path: "git")
  }

  static func resolveGitExecutableURL(environment: [String: String]) -> URL? {
    if let override = environment["SWIFT_GIT_REVISION_GIT_PATH"], !override.isEmpty {
      if let resolved = resolveExecutable(named: override, environment: environment) {
        return resolved
      }
    }

    if let resolved = resolveExecutable(named: "git", environment: environment) {
      return resolved
    }

    for fallback in fallbackGitPaths() {
      if let resolved = resolveExecutable(named: fallback, environment: environment) {
        return resolved
      }
    }

    return nil
  }

  private static func resolveExecutable(named name: String, environment: [String: String]) -> URL? {
    let expandedName = (name as NSString).expandingTildeInPath
    if expandedName.contains("/") || expandedName.contains("\\") {
      let url = URL(fileURLWithPath: expandedName)
      return isExecutableFile(at: url, environment: environment) ? url : nil
    }

    return resolveExecutableInPath(command: expandedName, environment: environment)
  }

  private static func resolveExecutableInPath(
    command: String,
    environment: [String: String]
  ) -> URL? {
    guard let pathValue = environment["PATH"], !pathValue.isEmpty else {
      return nil
    }

    let separator: Character = {
#if os(Windows)
      return ";"
#else
      return ":"
#endif
    }()

    let candidates = executableCandidates(for: command, environment: environment)

    for entry in pathValue.split(separator: separator) {
      let trimmed = String(entry).trimmingCharacters(in: .whitespacesAndNewlines)
        .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
      guard !trimmed.isEmpty else { continue }

      let baseURL = URL(fileURLWithPath: trimmed, isDirectory: true)
      for candidate in candidates {
        let url = baseURL.appendingPathComponent(candidate)
        if isExecutableFile(at: url, environment: environment) {
          return url
        }
      }
    }

    return nil
  }

  private static func executableCandidates(
    for command: String,
    environment: [String: String]
  ) -> [String] {
#if os(Windows)
    let extensionValue = URL(fileURLWithPath: command).pathExtension
    if !extensionValue.isEmpty {
      return [command]
    }

    return windowsExecutableExtensions(environment: environment).map { command + $0 }
#else
    return [command]
#endif
  }

  private static func isExecutableFile(at url: URL, environment: [String: String]) -> Bool {
#if os(Windows)
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
      !isDirectory.boolValue
    else {
      return false
    }

    let ext = "." + url.pathExtension.lowercased()
    return windowsExecutableExtensions(environment: environment).contains(ext)
#else
    return FileManager.default.isExecutableFile(atPath: url.path)
#endif
  }

#if os(Windows)
  private static func windowsExecutableExtensions(environment: [String: String]) -> [String] {
    if let pathext = environment["PATHEXT"], !pathext.isEmpty {
      return pathext
        .split(separator: ";")
        .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
        .map { value in
          let lowercased = value.lowercased()
          return lowercased.hasPrefix(".") ? lowercased : ".\(lowercased)"
        }
    }
    return [".exe", ".cmd", ".bat", ".com"]
  }
#endif

  private static func fallbackGitPaths() -> [String] {
#if os(macOS)
    return ["/usr/bin/git", "/usr/local/bin/git", "/opt/homebrew/bin/git"]
#elseif os(Linux)
    return ["/usr/bin/git", "/usr/local/bin/git", "/bin/git"]
#elseif os(Windows)
    return [
      "C:\\Program Files\\Git\\cmd\\git.exe",
      "C:\\Program Files\\Git\\bin\\git.exe",
      "C:\\Program Files (x86)\\Git\\cmd\\git.exe",
      "C:\\Program Files (x86)\\Git\\bin\\git.exe",
    ]
#else
    return ["/usr/bin/git"]
#endif
  }

  private func validateRepository(gitURL: URL) throws {
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: repositoryURL.path, isDirectory: &isDirectory),
      isDirectory.boolValue
    else {
      throw CollectorError.repositoryPathInvalid(path: repositoryURL.path)
    }

    let result = try runGit(arguments: [
      "rev-parse", "--is-inside-work-tree", "--is-bare-repository",
    ], gitURL: gitURL)
    guard result.exitCode == 0 else {
      throw mapGitFailure(result)
    }

    let lines = result.stdout
      .split(whereSeparator: \.isNewline)
      .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
    guard lines.count >= 2 else {
      throw CollectorError.unexpectedOutput(message: "expected 2 lines, got \(lines.count)")
    }

    guard let isInside = parseGitBoolean(lines[0]),
      let isBare = parseGitBoolean(lines[1])
    else {
      throw CollectorError.unexpectedOutput(message: "expected boolean values from rev-parse")
    }

    guard isInside || isBare else {
      throw CollectorError.notAGitRepository(path: repositoryURL.path)
    }
  }

  private func validateHasCommits(gitURL: URL) throws {
    let result = try runGit(arguments: ["rev-parse", "--verify", "HEAD"], gitURL: gitURL)
    guard result.exitCode == 0 else {
      if isNoCommitMessage(stdout: result.stdout, stderr: result.stderr) {
        throw CollectorError.noCommit
      }
      throw mapGitFailure(result)
    }
  }

  private func loadLastCommit(gitURL: URL) throws -> GitRevInfo.Commit {
    let separator = "\u{1F}"
    let format =
      "%H\(separator)%h\(separator)%an\(separator)%ae\(separator)%at\(separator)%cn\(separator)%ce\(separator)%ct\(separator)%s"
    let result = try runGit(arguments: ["show", "-s", "--format=\(format)"], gitURL: gitURL)

    guard result.exitCode == 0 else {
      if isNoCommitMessage(stdout: result.stdout, stderr: result.stderr) {
        throw CollectorError.noCommit
      }
      throw mapGitFailure(result)
    }

    let output = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    let parts = output.components(separatedBy: separator)
    guard parts.count == 9 else {
      throw CollectorError.unexpectedOutput(message: "expected 9 fields, got \(parts.count)")
    }

    let fullHash = parts[0]
    let shortHash = parts[1]
    let authorName = parts[2]
    let authorEmail = parts[3]
    let authorTimestamp = parts[4]
    let committerName = parts[5]
    let committerEmail = parts[6]
    let committerTimestamp = parts[7]
    let subjectField = parts[8]

    guard let authorSeconds = Double(authorTimestamp) else {
      throw CollectorError.unexpectedOutput(message: "invalid author timestamp")
    }
    guard let committerSeconds = Double(committerTimestamp) else {
      throw CollectorError.unexpectedOutput(message: "invalid committer timestamp")
    }

    let author = GitRevInfo.User(name: authorName, email: authorEmail)
    let committer = GitRevInfo.User(name: committerName, email: committerEmail)
    let subject = subjectField.isEmpty ? nil : subjectField

    return GitRevInfo.Commit(
      author: author,
      committer: committer,
      subject: subject,
      authorDate: Date(timeIntervalSince1970: authorSeconds),
      commitDate: Date(timeIntervalSince1970: committerSeconds),
      shortHash: shortHash,
      hash: fullHash
    )
  }

  private func loadBranchName(gitURL: URL) throws -> String? {
    let result = try runGit(arguments: ["symbolic-ref", "--short", "HEAD"], gitURL: gitURL)
    if result.exitCode == 0 {
      let branch = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
      return branch.isEmpty ? nil : branch
    }

    if isDetachedHeadMessage(stderr: result.stderr) {
      return nil
    }

    throw mapGitFailure(result)
  }

  private func runGit(arguments: [String], gitURL: URL) throws -> GitCommandResult {
    let process = Process()
    var environment = ProcessInfo.processInfo.environment
    environment["LC_ALL"] = "C"
    process.environment = environment

#if os(Windows)
    if isCommandScript(gitURL) {
      guard let commandInterpreter = Self.resolveCommandInterpreter(environment: environment) else {
        throw CollectorError.executableNotFound(path: "cmd.exe")
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
    process.currentDirectoryURL = repositoryURL

    let stdout = Pipe()
    let stderr = Pipe()
    process.standardOutput = stdout
    process.standardError = stderr

    do {
      try process.run()
    } catch {
      throw CollectorError.gitFailed(message: error.localizedDescription)
    }

    process.waitUntilExit()

    let stdoutData = stdout.fileHandleForReading.readDataToEndOfFile()
    let stderrData = stderr.fileHandleForReading.readDataToEndOfFile()
    let stdoutString = String(decoding: stdoutData, as: UTF8.self)
    let stderrString = String(decoding: stderrData, as: UTF8.self)

    return GitCommandResult(
      stdout: stdoutString,
      stderr: stderrString,
      exitCode: process.terminationStatus
    )
  }

#if os(Windows)
  private func isCommandScript(_ url: URL) -> Bool {
    let ext = url.pathExtension.lowercased()
    return ext == "cmd" || ext == "bat"
  }

  private static func resolveCommandInterpreter(
    environment: [String: String]
  ) -> URL? {
    if let comspec = environment["COMSPEC"], !comspec.isEmpty,
      let resolved = resolveExecutable(named: comspec, environment: environment)
    {
      return resolved
    }
    return resolveExecutable(named: "cmd.exe", environment: environment)
  }
#endif

  private func formatGitFailure(_ result: GitCommandResult) -> String {
    let stdout = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)

    if stdout.isEmpty && stderr.isEmpty {
      return "git command failed with no output"
    }
    if stdout.isEmpty {
      return stderr
    }
    if stderr.isEmpty {
      return stdout
    }

    return "stdout: \(stdout)\nstderr: \(stderr)"
  }

  private func isNoCommitMessage(stdout: String, stderr: String) -> Bool {
    let combined = (stdout + "\n" + stderr).lowercased()
    return combined.contains("does not have any commits yet")
      || combined.contains("needed a single revision") || combined.contains("unknown revision")
      || combined.contains("bad revision") || combined.contains("bad object head")
      || combined.contains("invalid object name") || combined.contains("ambiguous argument 'head'")
  }

  private func isDetachedHeadMessage(stderr: String) -> Bool {
    let message = stderr.lowercased()
    return message.contains("not a symbolic ref") || message.contains("detached")
  }

  private func parseGitBoolean(_ value: String) -> Bool? {
    switch value {
    case "true":
      return true
    case "false":
      return false
    default:
      return nil
    }
  }

  private func mapGitFailure(_ result: GitCommandResult) -> CollectorError {
    if isGitNotAvailableMessage(stdout: result.stdout, stderr: result.stderr) {
      return .gitNotAvailable(message: formatGitFailure(result))
    }
    if isUnsafeRepositoryMessage(stdout: result.stdout, stderr: result.stderr) {
      return .unsafeRepository(path: repositoryURL.path, message: formatGitFailure(result))
    }
    if isPermissionDeniedMessage(stdout: result.stdout, stderr: result.stderr) {
      return .repositoryPermissionDenied(
        path: repositoryURL.path, message: formatGitFailure(result))
    }
    if isNotRepositoryMessage(stdout: result.stdout, stderr: result.stderr) {
      return .notAGitRepository(path: repositoryURL.path)
    }
    return .gitFailed(message: formatGitFailure(result))
  }

  private func isNotRepositoryMessage(stdout: String, stderr: String) -> Bool {
    let combined = (stdout + "\n" + stderr).lowercased()
    return combined.contains("not a git repository")
  }

  private func isUnsafeRepositoryMessage(stdout: String, stderr: String) -> Bool {
    let combined = (stdout + "\n" + stderr).lowercased()
    return combined.contains("detected dubious ownership") || combined.contains("unsafe repository")
      || combined.contains("safe.directory")
  }

  private func isPermissionDeniedMessage(stdout: String, stderr: String) -> Bool {
    let combined = (stdout + "\n" + stderr).lowercased()
    return combined.contains("permission denied") || combined.contains("operation not permitted")
  }

  private func isGitNotAvailableMessage(stdout: String, stderr: String) -> Bool {
    let combined = (stdout + "\n" + stderr).lowercased()
    return combined.contains("xcrun: error") || combined.contains("xcode-select: error")
      || combined.contains("invalid active developer path") || combined.contains("requires xcode")
      || combined.contains("command line tools")
  }
}

private struct GitCommandResult {
  let stdout: String
  let stderr: String
  let exitCode: Int32
}

enum CollectorError: Error, LocalizedError {
  case executableNotFound(path: String)
  case repositoryPathInvalid(path: String)
  case notAGitRepository(path: String)
  case unsafeRepository(path: String, message: String)
  case repositoryPermissionDenied(path: String, message: String)
  case gitNotAvailable(message: String)
  case noCommit
  case gitFailed(message: String)
  case unexpectedOutput(message: String)

  var errorDescription: String? {
    switch self {
    case .executableNotFound(let path):
      return "git executable not found or not executable at \(path)"
    case .repositoryPathInvalid(let path):
      return "repository path '\(path)' is not a directory"
    case .notAGitRepository(let path):
      return "path '\(path)' is not a Git repository"
    case .unsafeRepository(let path, let message):
      return "git refused repository '\(path)' due to unsafe ownership: \(message)"
    case .repositoryPermissionDenied(let path, let message):
      return "permission denied while accessing repository '\(path)': \(message)"
    case .gitNotAvailable(let message):
      return "git is not available: \(message)"
    case .noCommit:
      return "repository has no commits"
    case .gitFailed(let message):
      return "git command failed: \(message)"
    case .unexpectedOutput(let message):
      return "unexpected git output: \(message)"
    }
  }
}
