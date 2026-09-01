import Foundation

/// Asks `git check-ignore` whether each path in a batch is ignored by `.gitignore`.
///
/// A small actor so the shell-out never touches the main thread. The batch API is
/// deliberate: `git check-ignore --stdin` handles thousands of paths in one process
/// invocation, which is cheap. Calling once per row would be O(N) forks.
///
/// The instance is stateless — it caches nothing — so callers pass exactly the set
/// they want answered. Cache invalidation belongs one layer up, in the store that
/// already tracks directory listings.
///
/// ```swift
/// let probe = GitIgnoreProbe()
/// let ignored = await probe.ignoredPaths(under: "/repo", paths: ["/repo/build", "/repo/README.md"])
/// // ignored == ["/repo/build"]
/// ```
actor GitIgnoreProbe {
    /// Returns the subset of `paths` that git considers ignored.
    ///
    /// - Parameters:
    ///   - repositoryRoot: Directory to run git in. When the path is not a git
    ///     repository the function returns an empty set — no report, no crash.
    ///   - paths: Absolute paths to check. Order need not match the return set;
    ///     the answer is a set for constant-time membership at the UI layer.
    /// - Returns: The absolute paths git said are ignored. Non-git repositories,
    ///   an unreadable stdin, or a launch failure all yield an empty set.
    func ignoredPaths(repositoryRoot: String, paths: [String]) async -> Set<String> {
        guard !paths.isEmpty else { return [] }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.currentDirectoryURL = URL(fileURLWithPath: repositoryRoot)
        // `-z` uses NUL as the record separator on stdin *and* stdout, which is the only
        // safe option in the presence of file names with spaces or newlines. `--stdin`
        // takes one path per record. `--no-index` is not what we want — that ignores the
        // git index and reads .gitignore rules only, but we still want the index to
        // exclude already-tracked files. `--verbose` would add reason columns, which we
        // do not consume.
        process.arguments = ["check-ignore", "-z", "--stdin"]
        var environment = ProcessInfo.processInfo.environment
        environment["GIT_OPTIONAL_LOCKS"] = "0"
        process.environment = environment

        let stdin = Pipe()
        let stdout = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return []
        }

        let input = paths.joined(separator: "\u{0}") + "\u{0}"
        stdin.fileHandleForWriting.write(Data(input.utf8))
        try? stdin.fileHandleForWriting.close()

        let outputData = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        // Exit code 0: at least one path is ignored. 1: none. 128: not a git repository.
        // The caller does not care which — a non-zero code with empty output means "no
        // rows to mark", which is exactly the right behaviour.
        guard let text = String(data: outputData, encoding: .utf8), !text.isEmpty else {
            return []
        }

        var reported: Set<String> = []
        // With `-z` git emits absolute paths in stdout only when the input was absolute.
        // We fed absolute paths in, so the output entries match `paths` byte-for-byte.
        for entry in text.split(separator: "\u{0}", omittingEmptySubsequences: true) {
            reported.insert(String(entry))
        }
        return reported
    }
}
