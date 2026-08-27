import Foundation

/// The seam through which the store reads git.
///
/// The store depends on this protocol rather than on ``GitHistoryService`` directly, so a
/// test can replace the real actor with a stub that returns canned pages, without the test
/// having to shell out to git.
protocol GitHistoryReading: Sendable {
    func page(repositoryRoot: String, maxCount: Int, skip: Int) async -> [GitCommitLine]
    func patch(repositoryRoot: String, sha: String) async -> String?
}

/// Runs git commands off the main thread for the history sidebar.
///
/// An actor rather than free functions because the constraint is temporal, not stateful:
/// `git log` on a large repository takes long enough that running it in `body` or a
/// synchronous helper freezes typing. Isolating the launches here means the call site is
/// always `await service.page(...)` and cannot forget.
///
/// The service holds no state of its own: it is a place for the git launcher to live off the
/// main thread. Caching, deduplication and paging live one layer up, in the store.
///
/// This intentionally does not use `Process`'s Foundation-preferred `async` API — it runs a
/// synchronous `Process` inside a `Task { }` and pipes the output. The reason: `Process`'s
/// standard-output pipe delivers via a callback that would need bridging, and the amount of
/// output for a page (a few thousand lines) fits comfortably in a single `readDataToEndOfFile`
/// once the child exits.
actor GitHistoryService: GitHistoryReading {
    /// Reads one page of the working tree's history.
    ///
    /// - Parameters:
    ///   - repositoryRoot: Absolute path of the repository (or any directory inside it; git
    ///     walks up to find `.git`).
    ///   - maxCount: Commits to return.
    ///   - skip: Commits to skip before returning.
    /// - Returns: The parsed page, oldest-most-recent-first (git's natural order). Empty
    ///   when git is not on the path, the path is not a repository, or the range is beyond
    ///   the last commit. Never `nil` — the caller cannot distinguish "no commits here" from
    ///   "error" and we would rather it treated both the same.
    func page(repositoryRoot: String, maxCount: Int, skip: Int) async -> [GitCommitLine] {
        let command = GitHistoryCommand(maxCount: maxCount, skip: skip)
        guard let output = run(arguments: command.arguments, repositoryRoot: repositoryRoot),
              !output.isEmpty
        else { return [] }
        return GitCommitLine.parseAll(output)
    }

    /// Returns the patch for one commit.
    ///
    /// - Parameters:
    ///   - repositoryRoot: Absolute path of the repository.
    ///   - sha: Full or short SHA. Passed as-is to `git show`.
    /// - Returns: The patch, or `nil` when git could not be launched or the output was empty.
    ///   An empty patch here is treated as absent — the historical failure mode that this
    ///   exists to prevent is exactly "the patch is empty and the click looks broken", so
    ///   returning `""` would defeat the point.
    func patch(repositoryRoot: String, sha: String) async -> String? {
        let command = GitCommitPatchCommand(sha: sha)
        guard let output = run(arguments: command.arguments, repositoryRoot: repositoryRoot),
              !output.isEmpty
        else { return nil }
        return output
    }

    /// Runs git and returns its standard output.
    ///
    /// Standard error is captured but discarded: this is a read-only path, and surfacing git
    /// error text in the sidebar is worse than showing "no history" — the user cannot act on
    /// it there anyway. `GIT_OPTIONAL_LOCKS=0` matches the setting used elsewhere in the app
    /// so a long-running local read never blocks the user's own `git commit`.
    private func run(arguments: [String], repositoryRoot: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.currentDirectoryURL = URL(fileURLWithPath: repositoryRoot)
        process.arguments = arguments
        var environment = ProcessInfo.processInfo.environment
        environment["GIT_OPTIONAL_LOCKS"] = "0"
        process.environment = environment
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8)
    }
}
