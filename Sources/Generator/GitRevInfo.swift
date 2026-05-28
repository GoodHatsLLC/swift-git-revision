// © GoodHatsLLC

import Foundation

/// Build-time representation of Git revision metadata.
struct GitRevInfo: Codable {
  /// Details for the most recent commit.
  let lastCommit: Commit
  /// Current branch name, or nil for detached HEAD.
  let branch: String?

  /// Full commit hash for the most recent commit.
  var hash: String {
    lastCommit.hash
  }

  /// Short commit hash for the most recent commit.
  var shortHash: String {
    lastCommit.shortHash
  }

  /// Creates revision info with a commit and branch.
  init(lastCommit: Commit, branch: String?) {
    self.lastCommit = lastCommit
    self.branch = branch
  }
}

extension GitRevInfo {
  /// Metadata for a Git commit.
  struct Commit: Codable {
    /// Commit author identity.
    let author: User
    /// Committer identity.
    let committer: User
    /// Commit subject, if available.
    let subject: String?
    /// Author timestamp.
    let authorDate: Date
    /// Committer timestamp.
    let commitDate: Date
    /// Short commit hash.
    let shortHash: String
    /// Full commit hash.
    let hash: String
  }

  /// A Git user identity.
  struct User: Codable, CustomStringConvertible {
    /// User name.
    let name: String
    /// User email.
    let email: String

    /// Creates a user identity.
    init(name: String, email: String) {
      self.name = name
      self.email = email
    }

    /// Returns the formatted identity as "Name <email>".
    var description: String {
      "\(name) <\(email)>"
    }
  }
}
