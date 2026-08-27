import Foundation

/// The `git` arguments that render one changed file as a patch.
///
/// Split out from the call site because picking the wrong revision to diff against is a silent
/// failure, not a visible one: the command succeeds and prints nothing, the caller drops the
/// empty patch, and the clicked row does nothing at all. Deciding the arguments in a value type
/// is what lets the decision be tested without a repository.
///
/// ```swift
/// let command = GitFilePatchCommand(filePath: "/repo/App.swift", isUntracked: false, hasHead: true)
/// // command.arguments == ["diff", "HEAD", "--", "/repo/App.swift"]
/// ```
struct GitFilePatchCommand: Equatable, Sendable {
    /// Arguments to pass to `git`, run with the repository as the working directory.
    let arguments: [String]

    /// Builds the command for one file.
    ///
    /// - Parameters:
    ///   - filePath: Absolute path of the changed file.
    ///   - isUntracked: Whether git has never tracked the file.
    ///   - hasHead: Whether the repository has a commit to diff against.
    init(filePath: String, isUntracked: Bool, hasHead: Bool) {
        if isUntracked || !hasHead {
            // Nothing to diff against: a file no commit contains produces an empty patch from
            // every revision-based form of `git diff`. Comparing it to /dev/null is what renders
            // it as an addition. A repository before its first commit has no `HEAD` at all, so
            // every file there takes this path.
            arguments = ["diff", "--no-index", "--", "/dev/null", filePath]
        } else {
            // Against `HEAD`, not the index. Plain `git diff` compares the work tree to the
            // index, so a file that has been `git add`ed shows no difference and its row goes
            // dead — which is exactly how staged files stopped opening.
            arguments = ["diff", "HEAD", "--", filePath]
        }
    }
}
