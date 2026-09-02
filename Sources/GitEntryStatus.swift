import Foundation

/// One file's git status, split into the index side (staged) and the working-tree side
/// (unstaged) that `git status --porcelain=v1` reports as `XY path`.
///
/// The pre-existing ``GitFileStatus`` folded the two sides into one enum so callers only
/// saw "this file changed"; that was fine for the sidebar's colour marks but there is no
/// way to build a stage/unstage UI on top of it. This type carries both sides
/// independently so the sidebar can render "Staged Changes" and "Changes" as separate
/// lists and each row can offer the operation that matches its side.
///
/// A file that has been staged and then edited again shows up with **both** sides set —
/// git spells this `MM`, and the sidebar renders it in both sections. That is the whole
/// reason for keeping the two sides split.
struct GitEntryStatus: Equatable, Sendable {
    /// Change on the index side, or `nil` when nothing is staged for this path.
    let staged: GitFileStatus?

    /// Change in the working tree, or `nil` when the file matches the index.
    let unstaged: GitFileStatus?

    /// Whether either side reports a change.
    var hasAny: Bool { staged != nil || unstaged != nil }

    /// One-status projection used for API compatibility with
    /// ``FileExplorerStore/gitStatusByPath`` and the outline's colour mark.
    ///
    /// Unstaged wins over staged when both sides are set. Reason: the working-tree state is
    /// what "the file looks like right now"; the sidebar's mark should reflect that. A file
    /// that is `MM` in git status reads as "modified" — the fact that some earlier version
    /// was staged is a Git tab detail, not something the general file tree needs to show.
    var displayStatus: GitFileStatus? { unstaged ?? staged }
}
