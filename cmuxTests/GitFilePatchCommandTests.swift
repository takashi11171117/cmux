import Foundation
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

/// Which git diff a Git sidebar row runs when clicked.
///
/// The bug this suite exists to prevent: picking the wrong `git diff` variant is silent.
/// The command exits 0 with no output, the caller drops the empty patch, and the row
/// stops working — no error, no tab, no diff. The argument tests pin each side; the
/// repository test proves the arguments mean what the rows promise, including before
/// the first commit, where an earlier version collapsed both sides into the same
/// whole-file patch.
@Suite("Git file patch command")
struct GitFilePatchCommandTests {
    private let path = "/repo/Sources/App.swift"

    @Test("Unstaged side runs plain `git diff -- <path>`")
    func unstagedSideRunsWorkingTreeDiff() {
        let command = GitFilePatchCommand(filePath: path, side: .unstaged)
        #expect(command.arguments == ["diff", "--", path])
    }

    @Test("Staged side runs `git diff --cached -- <path>`")
    func stagedSideRunsCachedDiff() {
        let command = GitFilePatchCommand(filePath: path, side: .staged)
        #expect(command.arguments == ["diff", "--cached", "--", path])
    }

    @Test("Untracked side renders the file against /dev/null")
    func untrackedSideUsesNoIndex() {
        let command = GitFilePatchCommand(filePath: path, side: .untracked)
        #expect(command.arguments == ["diff", "--no-index", "--", "/dev/null", path])
    }

    @Test("On an unborn branch an AM file yields distinct staged and unstaged patches")
    func unbornBranchKeepsStagedAndUnstagedPatchesDistinct() throws {
        // `git init`, `git add` with "a", then edit to "a\nb" without adding: status `AM`.
        // There is no HEAD yet. `--cached` must still show only the staged "a" (index vs
        // the empty tree) and plain `diff` only the later "b" (work tree vs index). The
        // regression this guards: falling back to `--no-index /dev/null` before the first
        // commit made both rows show the identical two-line file.
        let repoURL = try Self.makeTemporaryRepository()
        defer { try? FileManager.default.removeItem(at: repoURL) }

        let fileURL = repoURL.appendingPathComponent("f.txt")
        try "a\n".write(to: fileURL, atomically: true, encoding: .utf8)
        try Self.runGit(["add", "f.txt"], in: repoURL)
        try "a\nb\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let staged = try Self.runGit(
            GitFilePatchCommand(filePath: fileURL.path, side: .staged).arguments,
            in: repoURL
        )
        let unstaged = try Self.runGit(
            GitFilePatchCommand(filePath: fileURL.path, side: .unstaged).arguments,
            in: repoURL
        )

        #expect(staged.contains("\n+a\n"))
        #expect(!staged.contains("\n+b\n"))
        #expect(unstaged.contains("\n+b\n"))
        #expect(!unstaged.contains("\n+a\n"))
    }

    // MARK: - Helpers

    private static func makeTemporaryRepository() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("GitFilePatchCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        // `-c init.templateDir=` keeps user hook templates (e.g. git-secrets) out of the
        // fresh repository; same mitigation as FileExplorerGitStatusProviderTests.
        _ = try runGit(["-c", "init.templateDir=", "init", "-q"], in: url)
        return url
    }

    /// Runs git and returns standard output. `git diff` exits 1 when there is a
    /// difference, so only launch failures are treated as errors.
    @discardableResult
    private static func runGit(_ arguments: [String], in directory: URL) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = directory
        process.standardInput = FileHandle.nullDevice
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err
        try process.run()
        let outData = out.fileHandleForReading.readDataToEndOfFile()
        let errData = err.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let errText = String(data: errData, encoding: .utf8) ?? ""
        try #require(
            process.terminationStatus == 0 || process.terminationStatus == 1,
            "git \(arguments.joined(separator: " ")) failed [\(process.terminationStatus)]: \(errText)"
        )
        return String(data: outData, encoding: .utf8) ?? ""
    }
}
