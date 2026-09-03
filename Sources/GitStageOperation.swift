import Foundation

/// The git commands behind the Git tab's `+` / `−` / `↺` row buttons.
///
/// An actor so every `Process` wait happens off the main thread (NFR-S01). It holds no
/// state beyond its configuration, so one instance can serve every row.
///
/// - `stage` runs `git add -- <path>`.
/// - `unstage` runs `git reset -q -- <path>`, or `git rm --cached -q -- <path>` before the
///   first commit, where `git reset` fails with "ambiguous argument 'HEAD'".
/// - `discardUnstagedChanges` restores a tracked file from the index with
///   `git checkout -- <path>` (staged edits survive, matching SREQ-03), and moves an
///   untracked file to the Trash instead of deleting it (NFR-S03).
///
/// ```swift
/// let operation = GitStageOperation()
/// try await operation.stage(repositoryRoot: "/repo", path: "/repo/App.swift")
/// ```
actor GitStageOperation {
    /// A git command that exited non-zero. `errorDescription` carries git's own message so
    /// the failure sheet says what git said, not just that something failed.
    struct Failure: LocalizedError, Equatable {
        let command: String
        let detail: String

        var errorDescription: String? {
            let trimmed = detail.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? command : "\(command)\n\(trimmed)"
        }
    }

    /// Moves a file to the Trash. Main-actor because the app's shared implementation
    /// (`FileExplorerFileOperation.moveToTrash`) is; tests inject a recorder instead.
    typealias TrashAction = @MainActor (URL) throws -> Void

    private let gitExecutableURL: URL
    private let trash: TrashAction

    /// - Parameters:
    ///   - gitExecutableURL: The git binary. Defaults to the system git, same as the
    ///     status provider and the patch commands.
    ///   - trash: How untracked files are discarded. Defaults to the file explorer's
    ///     Move to Trash so the two entry points behave identically.
    init(
        gitExecutableURL: URL = URL(fileURLWithPath: "/usr/bin/git"),
        trash: @escaping TrashAction = { url in _ = try FileExplorerFileOperation.moveToTrash(url) }
    ) {
        self.gitExecutableURL = gitExecutableURL
        self.trash = trash
    }

    /// Stages one file: `git add -- <path>`. Also stages a deletion, since `git add` of a
    /// removed path records the removal.
    func stage(repositoryRoot: String, path: String) throws {
        try run(["add", "--", path], in: repositoryRoot)
    }

    /// Unstages one file, choosing the command by whether `HEAD` exists.
    func unstage(repositoryRoot: String, path: String) throws {
        if hasHead(repositoryRoot: repositoryRoot) {
            try run(["reset", "-q", "--", path], in: repositoryRoot)
        } else {
            try run(["rm", "--cached", "-q", "--", path], in: repositoryRoot)
        }
    }

    /// Throws away the working-tree changes of one file.
    ///
    /// - Parameters:
    ///   - repositoryRoot: Directory to run git in.
    ///   - path: Absolute path of the file.
    ///   - isUntracked: `true` sends the file to the Trash; `false` restores it from the
    ///     index, which keeps any staged edit in place.
    func discardUnstagedChanges(repositoryRoot: String, path: String, isUntracked: Bool) async throws {
        if isUntracked {
            let trash = trash
            try await MainActor.run { try trash(URL(fileURLWithPath: path)) }
        } else {
            try run(["checkout", "--", path], in: repositoryRoot)
        }
    }

    /// `--verify --quiet` prints the hash and says nothing when there is no `HEAD`.
    private func hasHead(repositoryRoot: String) -> Bool {
        let result = execute(["rev-parse", "--verify", "--quiet", "HEAD"], in: repositoryRoot)
        return result.status == 0 && !result.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func run(_ arguments: [String], in repositoryRoot: String) throws {
        let result = execute(arguments, in: repositoryRoot)
        guard result.status == 0 else {
            throw Failure(command: "git " + arguments.joined(separator: " "), detail: result.stderr)
        }
    }

    private func execute(_ arguments: [String], in repositoryRoot: String) -> (status: Int32, stdout: String, stderr: String) {
        let process = Process()
        process.executableURL = gitExecutableURL
        process.currentDirectoryURL = URL(fileURLWithPath: repositoryRoot)
        process.arguments = arguments
        var environment = ProcessInfo.processInfo.environment
        // Same non-locking mode as the status provider: never contend with the user's
        // own git for the index lock.
        environment["GIT_OPTIONAL_LOCKS"] = "0"
        process.environment = environment
        process.standardInput = FileHandle.nullDevice
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        do {
            try process.run()
        } catch {
            return (-1, "", error.localizedDescription)
        }
        let outData = stdout.fileHandleForReading.readDataToEndOfFile()
        let errData = stderr.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (
            process.terminationStatus,
            String(data: outData, encoding: .utf8) ?? "",
            String(data: errData, encoding: .utf8) ?? ""
        )
    }
}
