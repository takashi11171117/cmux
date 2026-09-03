import Foundation

/// The `git` arguments that render one changed file as a patch.
///
/// Split out from the call site because picking the wrong revision to diff against is a
/// silent failure, not a visible one: the command succeeds and prints nothing, the caller
/// drops the empty patch, and the clicked row does nothing at all. Deciding the arguments
/// in a value type is what lets the decision be tested without a repository.
///
/// ```swift
/// let command = GitFilePatchCommand(filePath: "/repo/App.swift", side: .unstaged, hasHead: true)
/// // command.arguments == ["diff", "--", "/repo/App.swift"]
/// ```
struct GitFilePatchCommand: Equatable, Sendable {
    /// Which side of the working-tree/index divide the diff comes from.
    enum Side: Equatable, Sendable {
        /// Working tree vs. index: `git diff -- <path>`. What "unstaged changes" means.
        case unstaged
        /// Index vs. HEAD: `git diff --cached -- <path>`. What "staged changes" means.
        case staged
        /// A file git has never tracked; rendered as a whole-file addition against
        /// `/dev/null` since no revision holds it.
        case untracked
    }

    /// Arguments to pass to `git`, run with the repository as the working directory.
    let arguments: [String]

    /// Builds the command for one file on the requested side.
    ///
    /// - Parameters:
    ///   - filePath: Absolute path of the changed file.
    ///   - side: Which diff to render.
    ///   - hasHead: Whether the repository has a commit to diff against. Before the first
    ///     commit both sides degrade to `--no-index /dev/null`, because there is nothing
    ///     to compare the file to on either side.
    init(filePath: String, side: Side, hasHead: Bool) {
        switch side {
        case .untracked:
            arguments = ["diff", "--no-index", "--", "/dev/null", filePath]
        case .staged:
            arguments = hasHead
                ? ["diff", "--cached", "--", filePath]
                : ["diff", "--no-index", "--", "/dev/null", filePath]
        case .unstaged:
            arguments = hasHead
                ? ["diff", "--", filePath]
                : ["diff", "--no-index", "--", "/dev/null", filePath]
        }
    }
}
