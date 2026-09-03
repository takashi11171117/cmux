import Foundation

/// The `git` arguments that render one changed file as a patch.
///
/// Split out from the call site because picking the wrong revision to diff against is a
/// silent failure, not a visible one: the command succeeds and prints nothing, the caller
/// drops the empty patch, and the clicked row does nothing at all. Deciding the arguments
/// in a value type is what lets the decision be tested without a repository.
///
/// Neither side needs `HEAD`. `git diff --cached` compares the index to the empty tree on
/// an unborn branch, and plain `git diff` never looks at `HEAD` at all, so a repository
/// with no commits yet gets the same two distinct patches as any other — an `AM` file
/// shows its staged content on one row and only the later edit on the other. (An earlier
/// version degraded both sides to `--no-index /dev/null` before the first commit, which
/// made those two rows show the identical whole-file patch.)
///
/// ```swift
/// let command = GitFilePatchCommand(filePath: "/repo/App.swift", side: .unstaged)
/// // command.arguments == ["diff", "--", "/repo/App.swift"]
/// ```
struct GitFilePatchCommand: Equatable, Sendable {
    /// Which side of the working-tree/index divide the diff comes from.
    enum Side: Equatable, Sendable {
        /// Working tree vs. index: `git diff -- <path>`. What "unstaged changes" means.
        case unstaged
        /// Index vs. HEAD (or the empty tree before the first commit):
        /// `git diff --cached -- <path>`. What "staged changes" means.
        case staged
        /// A file git has never tracked; rendered as a whole-file addition against
        /// `/dev/null` since neither the index nor any revision holds it.
        case untracked
    }

    /// Arguments to pass to `git`, run with the repository as the working directory.
    let arguments: [String]

    /// Builds the command for one file on the requested side.
    ///
    /// - Parameters:
    ///   - filePath: Absolute path of the changed file.
    ///   - side: Which diff to render.
    init(filePath: String, side: Side) {
        switch side {
        case .untracked:
            arguments = ["diff", "--no-index", "--", "/dev/null", filePath]
        case .staged:
            arguments = ["diff", "--cached", "--", filePath]
        case .unstaged:
            arguments = ["diff", "--", filePath]
        }
    }
}
