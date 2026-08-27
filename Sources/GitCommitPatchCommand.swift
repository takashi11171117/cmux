import Foundation

/// The `git` arguments that render one commit as a patch.
///
/// Split out from the call site because picking the wrong flag turns "the merge commit" into
/// "empty output": `git show <sha>` on a merge is 0 lines by default, the caller drops the
/// empty patch, and the clicked row does nothing at all — the same shape of silent failure
/// as `GitFilePatchCommand`. Deciding the arguments in a value type is what lets the
/// decision be tested without a repository.
///
/// **Always `--first-parent`.** Measured on 2026-08-27:
///
/// | option | root | normal | merge |
/// | --- | --- | --- | --- |
/// | (none) | 8 | 7 | **0** ← row goes dead |
/// | `--first-parent` | 8 | 7 | **7** |
///
/// `--root` is unnecessary; `git show` handles a root commit on its own. `--first-parent` on
/// a normal commit does not change the output, so it is applied unconditionally rather than
/// branched on commit shape — the branch would be another place to forget.
///
/// ```swift
/// let command = GitCommitPatchCommand(sha: "a1b2c3d")
/// // command.arguments == ["show", "--format=", "--patch", "--first-parent", "a1b2c3d"]
/// ```
struct GitCommitPatchCommand: Equatable, Sendable {
    /// Arguments to pass to `git`, run with the repository as the working directory.
    let arguments: [String]

    /// Builds the command for one commit.
    ///
    /// - Parameter sha: The commit to render. May be a full or short SHA; git accepts both.
    init(sha: String) {
        arguments = [
            "show",
            "--format=",
            "--patch",
            "--first-parent",
            sha,
        ]
    }
}
