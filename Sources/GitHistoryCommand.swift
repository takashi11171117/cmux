import Foundation

/// The `git log` arguments that fetch one page of commit history.
///
/// A page is the wrong unit for the caller to pin down (fields, encoding, delimiter) every
/// time it wants more history. Building the argument list from `(maxCount, skip)` keeps the
/// output format in one place and the paging arithmetic tested without a repository.
///
/// The pretty format keeps every field on one line, delimits with `NUL` so nothing in the
/// commit — including a `|` or a tab in the subject — can break parsing, and ends each record
/// with a full `NUL` so a truncated tail is discardable, not misparsed.
///
/// ```swift
/// let command = GitHistoryCommand(maxCount: 200, skip: 0)
/// // git log --max-count=200 --skip=0 --pretty=format:%H%x00%h%x00%P%x00%an%x00%aI%x00%s%x00 --date=iso-strict
/// ```
struct GitHistoryCommand: Equatable, Sendable {
    /// Arguments to pass to `git`, run with the repository as the working directory.
    let arguments: [String]

    /// Field order matches ``GitCommitLine`` and is documented alongside the parser to keep
    /// producer and consumer in one place.
    ///
    /// Order: full sha, short sha, parents (space-separated, possibly empty), author name,
    /// authored ISO-strict date, subject (line 1).
    static let prettyFormat = "%H%x00%h%x00%P%x00%an%x00%aI%x00%s%x00"

    /// Builds the command for a page.
    ///
    /// - Parameters:
    ///   - maxCount: Commits to return in this page. Non-positive values are treated as 1;
    ///     `git log --max-count=0` is legal but returns nothing, which makes the mistake at
    ///     the call site look like "history reached the end" and hides the bug.
    ///   - skip: Commits to skip before returning. Negative values are treated as 0 for the
    ///     same reason.
    init(maxCount: Int, skip: Int) {
        let safeCount = max(1, maxCount)
        let safeSkip = max(0, skip)
        arguments = [
            "log",
            "--max-count=\(safeCount)",
            "--skip=\(safeSkip)",
            "--pretty=format:\(Self.prettyFormat)",
            "--date=iso-strict",
        ]
    }
}
