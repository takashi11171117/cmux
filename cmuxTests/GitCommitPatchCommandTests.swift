import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

/// Which flags `git show` runs with.
///
/// The bug these prevent: `git show <sha>` on a merge is 0 lines by default. The caller drops
/// an empty patch and the clicked row does nothing at all — same shape of silent failure
/// found in ``GitFilePatchCommand``. Measured 2026-08-27.
@Suite("Git commit patch command")
struct GitCommitPatchCommandTests {
    @Test("A commit patch is taken with --first-parent")
    func alwaysFirstParent() {
        let command = GitCommitPatchCommand(sha: "a1b2c3d")

        #expect(command.arguments.contains("--first-parent"))
    }

    @Test("The command is exactly the documented shape")
    func documentedShape() {
        let command = GitCommitPatchCommand(sha: "a1b2c3d")

        #expect(command.arguments == ["show", "--format=", "--patch", "--first-parent", "a1b2c3d"])
    }

    @Test("The SHA is passed through untouched")
    func shaPassesThrough() {
        let command = GitCommitPatchCommand(sha: "abcdef0123456789")

        #expect(command.arguments.last == "abcdef0123456789")
    }
}
