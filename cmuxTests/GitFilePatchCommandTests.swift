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
/// stops working — no error, no tab, no diff. Every side / has-HEAD combination gets an
/// assertion so future edits do not regress into that class of silence.
@Suite("Git file patch command")
struct GitFilePatchCommandTests {
    private let path = "/repo/Sources/App.swift"

    // MARK: Unstaged side

    @Test("Unstaged side runs plain `git diff -- <path>`")
    func unstagedSideRunsWorkingTreeDiff() {
        let command = GitFilePatchCommand(filePath: path, side: .unstaged, hasHead: true)
        #expect(command.arguments == ["diff", "--", path])
    }

    @Test("Unstaged side before the first commit degrades to --no-index")
    func unstagedSideBeforeFirstCommitFallsBackToNoIndex() {
        // Nothing to diff the work tree against: no index yet, no HEAD. `--no-index`
        // against /dev/null renders the file as an addition. Same fallback the untracked
        // path already used, applied here so the row does not silently show nothing.
        let command = GitFilePatchCommand(filePath: path, side: .unstaged, hasHead: false)
        #expect(command.arguments == ["diff", "--no-index", "--", "/dev/null", path])
    }

    // MARK: Staged side

    @Test("Staged side runs `git diff --cached -- <path>`")
    func stagedSideRunsCachedDiff() {
        let command = GitFilePatchCommand(filePath: path, side: .staged, hasHead: true)
        #expect(command.arguments == ["diff", "--cached", "--", path])
    }

    @Test("Staged side before the first commit falls back to --no-index")
    func stagedSideBeforeFirstCommitFallsBackToNoIndex() {
        // A fresh `git init` + `git add file` produces a staged addition; there is no HEAD
        // to diff against, so `git diff --cached` returns nothing. Rendering the file
        // against /dev/null keeps the row usable in that state.
        let command = GitFilePatchCommand(filePath: path, side: .staged, hasHead: false)
        #expect(command.arguments == ["diff", "--no-index", "--", "/dev/null", path])
    }

    // MARK: Untracked side

    @Test("Untracked side runs --no-index regardless of HEAD")
    func untrackedSideAlwaysUsesNoIndex() {
        // Untracked files never live in a revision, so the answer is identical whether
        // or not HEAD exists. Guarding both cases makes it a documented invariant.
        for hasHead in [true, false] {
            let command = GitFilePatchCommand(filePath: path, side: .untracked, hasHead: hasHead)
            #expect(command.arguments == ["diff", "--no-index", "--", "/dev/null", path])
        }
    }
}
