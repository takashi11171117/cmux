import Foundation
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

@Suite(.serialized)
struct FileExplorerGitStatusProviderTests {
    @Test
    func statusQueryDoesNotRefreshGitIndex() throws {
        let repoURL = try Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: repoURL) }

        try Self.initializeRepo(at: repoURL)

        let trackedURL = repoURL.appendingPathComponent("tracked.txt")
        try "one\n".write(to: trackedURL, atomically: true, encoding: .utf8)
        try Self.runGit(["add", "tracked.txt"], in: repoURL)
        try Self.runGit(["commit", "-m", "initial"], in: repoURL)

        let indexURL = repoURL.appendingPathComponent(".git/index")
        let indexBeforeStatus = try Data(contentsOf: indexURL)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSinceNow: 10)],
            ofItemAtPath: trackedURL.path
        )

        _ = GitStatusProvider().fetchStatus(directory: repoURL.path)

        let indexAfterStatus = try Data(contentsOf: indexURL)
        #expect(indexAfterStatus == indexBeforeStatus)
    }

    @Test
    func statusQueryPreservesQuotedAndEscapedFilenames() throws {
        let repoURL = try Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: repoURL) }
        try Self.initializeRepo(at: repoURL)

        let nestedURL = repoURL.appendingPathComponent("nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nestedURL, withIntermediateDirectories: true)
        let trackedURL = nestedURL.appendingPathComponent("quoted \"name\" and \\ slash.txt")
        try "one\n".write(to: trackedURL, atomically: true, encoding: .utf8)
        try Self.runGit(["add", "."], in: repoURL)
        try Self.runGit(["commit", "-m", "initial"], in: repoURL)
        try "two\n".write(to: trackedURL, atomically: true, encoding: .utf8)

        let status = GitStatusProvider().fetchStatus(directory: nestedURL.path)

        #expect(status[trackedURL.path]?.displayStatus == .modified)
    }

    @Test
    func statusQueryExcludesSiblingPathPrefixes() throws {
        let repoURL = try Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: repoURL) }
        try Self.initializeRepo(at: repoURL)

        let explorerRootURL = repoURL.appendingPathComponent("work", isDirectory: true)
        let siblingURL = repoURL.appendingPathComponent("workspace-sibling", isDirectory: true)
        try FileManager.default.createDirectory(at: explorerRootURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: siblingURL, withIntermediateDirectories: true)

        let visibleURL = explorerRootURL.appendingPathComponent("tracked.txt")
        let siblingFileURL = siblingURL.appendingPathComponent("tracked.txt")
        try "one\n".write(to: visibleURL, atomically: true, encoding: .utf8)
        try "one\n".write(to: siblingFileURL, atomically: true, encoding: .utf8)
        try Self.runGit(["add", "."], in: repoURL)
        try Self.runGit(["commit", "-m", "initial"], in: repoURL)
        try "two\n".write(to: visibleURL, atomically: true, encoding: .utf8)
        try "two\n".write(to: siblingFileURL, atomically: true, encoding: .utf8)

        let status = GitStatusProvider().fetchStatus(directory: explorerRootURL.path)

        #expect(status[visibleURL.path]?.displayStatus == .modified)
        #expect(status[siblingFileURL.path] == nil)
        #expect(status[siblingURL.path] == nil)
    }

    @Test
    func statusQueryMapsTypeChangedAndUnmergedEntries() throws {
        let repoURL = try Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: repoURL) }

        let fakeGitURL = try Self.writeExecutableScript(
            #"""
            #!/bin/sh
            if [ "${CMUX_TEST_GIT_ENV:-}" != "expected" ]; then
                exit 3
            fi
            if [ "${GIT_OPTIONAL_LOCKS:-}" != "0" ]; then
                exit 4
            fi
            case "$1 $2" in
            "rev-parse --show-toplevel")
                printf '%s\n' "$CMUX_TEST_REPO_ROOT"
                ;;
            "status --porcelain=v1")
                printf ' T type-change.txt\0UU conflicted.txt\0'
                ;;
            *)
                exit 2
                ;;
            esac
            """#,
            named: "fake-git",
            in: repoURL
        )
        var environment = ProcessInfo.processInfo.environment
        environment["CMUX_TEST_GIT_ENV"] = "expected"
        environment["CMUX_TEST_REPO_ROOT"] = repoURL.path

        let status = GitStatusProvider(
            gitExecutableURL: fakeGitURL,
            environment: environment
        ).fetchStatus(directory: repoURL.path)

        #expect(
            status[repoURL.appendingPathComponent("type-change.txt").path]?.displayStatus == .modified
        )
        #expect(
            status[repoURL.appendingPathComponent("conflicted.txt").path]?.displayStatus == .modified
        )
    }

    @Test
    func sshStatusQueryUsesInjectedProcessEnvironment() throws {
        let repoURL = try Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: repoURL) }

        let fakeSSHURL = try Self.writeExecutableScript(
            #"""
            #!/bin/sh
            if [ "${CMUX_TEST_SSH_ENV:-}" != "expected" ]; then
                exit 3
            fi
            printf '%s\n---GIT_STATUS---\n M remote.txt\0' "$CMUX_TEST_REPO_ROOT"
            """#,
            named: "fake-ssh",
            in: repoURL
        )
        var environment = ProcessInfo.processInfo.environment
        environment["CMUX_TEST_REPO_ROOT"] = repoURL.path
        environment["CMUX_TEST_SSH_ENV"] = "expected"

        let status = GitStatusProvider(
            sshExecutableURL: fakeSSHURL,
            environment: environment
        ).fetchStatusSSH(
            directory: repoURL.path,
            destination: "example.invalid",
            port: nil,
            identityFile: nil,
            sshOptions: []
        )

        #expect(
            status[repoURL.appendingPathComponent("remote.txt").path]?.displayStatus == .modified
        )
    }

    @Test
    func sshStatusQueryOverridesHostConfiguredRemoteCommand() throws {
        // The remote git status runs as an ssh command-line command, which
        // OpenSSH refuses while a host-configured RemoteCommand is in effect
        // (issue #7246) — the argv must carry `-o RemoteCommand=none` before
        // the destination.
        let repoURL = try Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: repoURL) }

        let argvLog = repoURL.appendingPathComponent("ssh-argv.txt")
        let fakeSSHURL = try Self.writeExecutableScript(
            #"""
            #!/bin/sh
            for arg in "$@"; do printf '%s\n' "$arg"; done > "$CMUX_TEST_SSH_ARGV_LOG"
            printf '%s\n---GIT_STATUS---\n M remote.txt\0' "$CMUX_TEST_REPO_ROOT"
            """#,
            named: "fake-ssh",
            in: repoURL
        )
        var environment = ProcessInfo.processInfo.environment
        environment["CMUX_TEST_REPO_ROOT"] = repoURL.path
        environment["CMUX_TEST_SSH_ARGV_LOG"] = argvLog.path

        let status = GitStatusProvider(
            sshExecutableURL: fakeSSHURL,
            environment: environment
        ).fetchStatusSSH(
            directory: repoURL.path,
            destination: "example.invalid",
            port: nil,
            identityFile: nil,
            sshOptions: []
        )

        #expect(
            status[repoURL.appendingPathComponent("remote.txt").path]?.displayStatus == .modified
        )
        let argv = try String(contentsOf: argvLog, encoding: .utf8)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
        let overrideIndex = argv.indices.dropLast().first {
            argv[$0] == "-o" && argv[$0 + 1] == "RemoteCommand=none"
        }
        let destinationIndex = argv.firstIndex(of: "example.invalid")
        #expect(overrideIndex != nil, "\(argv)")
        #expect(destinationIndex != nil, "\(argv)")
        if let overrideIndex, let destinationIndex {
            #expect(overrideIndex < destinationIndex)
        }
    }

    @Test
    func statusQuerySplitsRenameRecordsAndKeepsTheFollowingEntry() throws {
        // `--porcelain=v1 -z` emits a rename as TWO NUL-terminated fields
        // (`R  new\0old\0`). A parser that treats the old path as the next record would
        // mislabel `old` as a change and lose the entry that really follows.
        let repoURL = try Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: repoURL) }
        try Self.initializeRepo(at: repoURL)

        let oldURL = repoURL.appendingPathComponent("old name.txt")
        try "one\n".write(to: oldURL, atomically: true, encoding: .utf8)
        try Self.runGit(["add", "."], in: repoURL)
        try Self.runGit(["commit", "-m", "initial"], in: repoURL)
        try Self.runGit(["mv", "old name.txt", "new name.txt"], in: repoURL)
        let addedURL = repoURL.appendingPathComponent("after rename.txt")
        try "two\n".write(to: addedURL, atomically: true, encoding: .utf8)
        try Self.runGit(["add", "after rename.txt"], in: repoURL)

        let status = GitStatusProvider().fetchStatus(directory: repoURL.path)

        let renamed = status[repoURL.appendingPathComponent("new name.txt").path]
        #expect(renamed?.staged == .renamed)
        #expect(renamed?.unstaged == nil)
        #expect(status[oldURL.path] == nil)
        let added = status[addedURL.path]
        #expect(added?.staged == .added)
        #expect(added?.unstaged == nil)
    }

    @Test
    func statusQueryListsUntrackedFilesIndividually() throws {
        // Without `--untracked-files=all`, git reports a whole untracked directory as
        // one `?? dir/` entry. That row cannot be opened as a single-file patch and is
        // counted as one change no matter how many files it hides.
        let repoURL = try Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: repoURL) }
        try Self.initializeRepo(at: repoURL)

        let dirURL = repoURL.appendingPathComponent("fresh", isDirectory: true)
        try FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)
        let firstURL = dirURL.appendingPathComponent("a.txt")
        let secondURL = dirURL.appendingPathComponent("b.txt")
        try "a\n".write(to: firstURL, atomically: true, encoding: .utf8)
        try "b\n".write(to: secondURL, atomically: true, encoding: .utf8)

        let status = GitStatusProvider().fetchStatus(directory: repoURL.path)

        #expect(status[firstURL.path]?.unstaged == .untracked)
        #expect(status[secondURL.path]?.unstaged == .untracked)
        // The directory itself only appears as the synthesized folder marker.
        #expect(status[dirURL.path]?.isDirectoryMarker == true)
    }

    private static func makeTemporaryDirectory() throws -> URL {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("cmux-file-explorer-git-status-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        return rootURL
    }

    private static func writeExecutableScript(
        _ contents: String, named name: String, in directory: URL
    ) throws -> URL {
        let scriptURL = directory.appendingPathComponent(name)
        try contents.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
        return scriptURL
    }

    private static func initializeRepo(at repoURL: URL) throws {
        try Self.runGit(["init"], in: repoURL)
        try Self.runGit(["config", "user.name", "cmux tests"], in: repoURL)
        try Self.runGit(["config", "user.email", "cmux@example.invalid"], in: repoURL)
    }

    private static func runGit(_ arguments: [String], in directory: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        // Skip user-side pre-commit hooks under test. The test runner may inherit hooks
        // like `git-secrets` from a global config; those are outside this test's contract
        // and their absence-or-presence makes the harness flake ("git: 'secrets' is not a
        // git command"). Prepending `--no-verify` after `commit` isolates us from that.
        // Skip user-side pre-commit hooks under test. The test runner may inherit hooks
        // like `git-secrets` from a global `init.templateDir`; those hooks fail if the
        // corresponding tool is not installed on this machine and break the harness with
        // "git: 'secrets' is not a git command". Two mitigations, applied together:
        //   1. `git init` runs with `-c init.templateDir=` so the fresh repo has no user
        //      hook templates copied into it.
        //   2. `git commit` still gets `--no-verify` as a belt-and-suspenders defence in
        //      case something else (config-driven hookspath, per-repo hooks) sneaks in.
        var safeArguments = arguments
        if safeArguments.first == "init" {
            safeArguments.insert(contentsOf: ["-c", "init.templateDir="], at: 0)
        }
        if safeArguments.first == "commit" {
            safeArguments.insert("--no-verify", at: 1)
        }
        process.arguments = safeArguments
        process.currentDirectoryURL = directory
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        // stderr goes to a pipe (not nullDevice) so a `#require` failure carries the
        // actual git error text — that is how the `git-secrets` template-hook issue was
        // diagnosed. Without this the assertion just says `terminationStatus → 1` and the
        // culprit is impossible to see from CI logs.
        let errPipe = Pipe()
        process.standardError = errPipe

        try process.run()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        let errText = String(data: errData, encoding: .utf8) ?? ""
        try #require(
            process.terminationStatus == 0,
            "git \(safeArguments.joined(separator: " ")) failed [\(process.terminationStatus)]: \(errText)"
        )
    }
}
