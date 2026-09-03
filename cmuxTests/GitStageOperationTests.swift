import Foundation
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

/// The Git tab's `+` / `−` / `↺` buttons, run against real repositories.
///
/// Each test reads back `git status --porcelain` rather than trusting the command's exit
/// code: the failure mode these guard is "the button did something, just not what the
/// row promised" (unstaging before the first commit, discarding a staged edit along with
/// the unstaged one).
@Suite(.serialized)
struct GitStageOperationTests {
    @Test("`+` stages a modified file")
    func stageMovesAWorkingTreeEditToTheIndex() async throws {
        let repo = try Repo.make()
        defer { repo.remove() }
        try repo.commit(file: "a.txt", content: "one\n")
        try repo.write(file: "a.txt", content: "two\n")
        #expect(try repo.status() == [" M a.txt"])

        try await GitStageOperation().stage(repositoryRoot: repo.url.path, path: repo.path("a.txt"))

        #expect(try repo.status() == ["M  a.txt"])
    }

    @Test("`−` unstages with `git reset` once HEAD exists")
    func unstageAfterFirstCommitUsesReset() async throws {
        let repo = try Repo.make()
        defer { repo.remove() }
        try repo.commit(file: "a.txt", content: "one\n")
        try repo.write(file: "a.txt", content: "two\n")
        try repo.git(["add", "a.txt"])
        #expect(try repo.status() == ["M  a.txt"])

        try await GitStageOperation().unstage(repositoryRoot: repo.url.path, path: repo.path("a.txt"))

        #expect(try repo.status() == [" M a.txt"])
    }

    @Test("`−` before the first commit falls back to `git rm --cached`")
    func unstageBeforeFirstCommitFallsBackToRmCached() async throws {
        // `git reset -- <path>` fails here with "ambiguous argument 'HEAD'"; the file must
        // go back to untracked, and its content must survive (`--cached`).
        let repo = try Repo.make()
        defer { repo.remove() }
        try repo.write(file: "new.txt", content: "fresh\n")
        try repo.git(["add", "new.txt"])
        #expect(try repo.status() == ["A  new.txt"])

        try await GitStageOperation().unstage(repositoryRoot: repo.url.path, path: repo.path("new.txt"))

        #expect(try repo.status() == ["?? new.txt"])
        #expect(try String(contentsOfFile: repo.path("new.txt"), encoding: .utf8) == "fresh\n")
    }

    @Test("`↺` on a tracked MM file drops only the unstaged edit")
    func discardTrackedKeepsTheStagedEdit() async throws {
        let repo = try Repo.make()
        defer { repo.remove() }
        try repo.commit(file: "a.txt", content: "one\n")
        try repo.write(file: "a.txt", content: "one\ntwo\n")
        try repo.git(["add", "a.txt"])
        try repo.write(file: "a.txt", content: "one\ntwo\nthree\n")
        #expect(try repo.status() == ["MM a.txt"])

        try await GitStageOperation().discardUnstagedChanges(
            repositoryRoot: repo.url.path, path: repo.path("a.txt"), isUntracked: false
        )

        #expect(try repo.status() == ["M  a.txt"])
        #expect(try String(contentsOfFile: repo.path("a.txt"), encoding: .utf8) == "one\ntwo\n")
    }

    @Test("`↺` on an untracked file goes through the injected Trash action, never git")
    @MainActor
    func discardUntrackedUsesTheTrashAction() async throws {
        let repo = try Repo.make()
        defer { repo.remove() }
        try repo.write(file: "junk.txt", content: "x\n")
        #expect(try repo.status() == ["?? junk.txt"])

        let recorder = TrashRecorder()
        let operation = GitStageOperation(trash: { url in recorder.urls.append(url) })
        try await operation.discardUnstagedChanges(
            repositoryRoot: repo.url.path, path: repo.path("junk.txt"), isUntracked: true
        )

        #expect(recorder.urls.map(\.lastPathComponent) == ["junk.txt"])
        // The recorder did not touch the disk, so the file is still there: proof that
        // untracked discard never runs `rm` or `git clean` behind the Trash action.
        #expect(FileManager.default.fileExists(atPath: repo.path("junk.txt")))
    }

    @Test("A failing git command surfaces git's own message")
    func failureCarriesGitStderr() async throws {
        let repo = try Repo.make()
        defer { repo.remove() }

        await #expect(throws: GitStageOperation.Failure.self) {
            try await GitStageOperation().stage(repositoryRoot: repo.url.path, path: repo.path("missing.txt"))
        }
    }

    // MARK: - Helpers

    /// Main-actor because `GitStageOperation.TrashAction` is: the real implementation
    /// wraps `FileExplorerFileOperation.moveToTrash`, which is `@MainActor`.
    @MainActor
    private final class TrashRecorder {
        var urls: [URL] = []
    }

    private struct Repo {
        let url: URL

        static func make() throws -> Repo {
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("GitStageOperationTests-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            let repo = Repo(url: url)
            // `-c init.templateDir=` keeps user hook templates (git-secrets) out of the
            // fresh repository; same mitigation as FileExplorerGitStatusProviderTests.
            try repo.git(["-c", "init.templateDir=", "init", "-q"])
            try repo.git(["config", "user.email", "test@example.com"])
            try repo.git(["config", "user.name", "Test"])
            return repo
        }

        func remove() { try? FileManager.default.removeItem(at: url) }

        func path(_ file: String) -> String { url.appendingPathComponent(file).path }

        func write(file: String, content: String) throws {
            try content.write(toFile: path(file), atomically: true, encoding: .utf8)
        }

        func commit(file: String, content: String) throws {
            try write(file: file, content: content)
            try git(["add", file])
            try git(["commit", "-q", "--no-verify", "-m", "commit \(file)"])
        }

        func status() throws -> [String] {
            try gitOutput(["status", "--porcelain=v1", "--untracked-files=all"])
                .split(separator: "\n").map(String.init)
        }

        func git(_ arguments: [String]) throws { _ = try gitOutput(arguments) }

        @discardableResult
        func gitOutput(_ arguments: [String]) throws -> String {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            process.arguments = arguments
            process.currentDirectoryURL = url
            process.standardInput = FileHandle.nullDevice
            let out = Pipe(), err = Pipe()
            process.standardOutput = out
            process.standardError = err
            try process.run()
            let outData = out.fileHandleForReading.readDataToEndOfFile()
            let errData = err.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            try #require(
                process.terminationStatus == 0,
                "git \(arguments.joined(separator: " ")) failed: \(String(data: errData, encoding: .utf8) ?? "")"
            )
            return String(data: outData, encoding: .utf8) ?? ""
        }
    }
}
