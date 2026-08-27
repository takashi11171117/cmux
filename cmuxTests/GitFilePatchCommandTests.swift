import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

/// Which revision a file's patch is taken against.
///
/// The bug these cover: plain `git diff` compares the work tree to the index, so every staged
/// file produced an empty patch, the caller dropped it, and clicking the row in the Git sidebar
/// did nothing at all — no error, no tab, no diff.
@Suite("Git file patch command")
struct GitFilePatchCommandTests {
    @Test("A staged file is diffed against HEAD, not the index")
    func stagedFileDiffsAgainstHead() {
        let command = GitFilePatchCommand(
            filePath: "/repo/Sources/App.swift",
            isUntracked: false,
            hasHead: true
        )

        #expect(command.arguments == ["diff", "HEAD", "--", "/repo/Sources/App.swift"])
    }

    @Test("A tracked file never uses the bare form that skips staged changes")
    func trackedFileNeverUsesBareDiff() {
        let command = GitFilePatchCommand(
            filePath: "/repo/Makefile",
            isUntracked: false,
            hasHead: true
        )

        #expect(command.arguments != ["diff", "--", "/repo/Makefile"])
    }

    @Test("An untracked file is rendered as an addition against /dev/null")
    func untrackedFileDiffsAgainstDevNull() {
        let command = GitFilePatchCommand(
            filePath: "/repo/Sources/New.swift",
            isUntracked: true,
            hasHead: true
        )

        #expect(command.arguments == [
            "diff", "--no-index", "--", "/dev/null", "/repo/Sources/New.swift",
        ])
    }

    @Test("Before the first commit there is no HEAD to diff against")
    func repositoryWithoutHeadDiffsAgainstDevNull() {
        let command = GitFilePatchCommand(
            filePath: "/repo/f.txt",
            isUntracked: false,
            hasHead: false
        )

        #expect(command.arguments == ["diff", "--no-index", "--", "/dev/null", "/repo/f.txt"])
    }
}
