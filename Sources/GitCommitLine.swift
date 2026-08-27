import Foundation

/// One commit as the history sidebar shows it.
///
/// A value type rather than a view model, for the same reason as ``GitChangeEntry``: rows sit
/// under a `ForEach`, and anything holding an observable store below that boundary
/// reintroduces the spin loop this codebase already fixed once (upstream #2586). Rows get
/// values and callbacks, never the store.
///
/// The parser stays here alongside the type so producer and consumer share one file and one
/// coordinate space; ``GitHistoryCommand/prettyFormat`` is the other half of the contract.
struct GitCommitLine: Identifiable, Equatable, Sendable {
    /// Full commit SHA. Used as the identity, so the row is stable across refreshes.
    let sha: String
    /// Short commit SHA, as `git log` prints it — length depends on the repository size.
    let shortSHA: String
    /// Parent commit SHAs. Empty for a root commit, one for a normal commit, more than one
    /// for a merge. This is what the graph layout will read; the sidebar shows nothing but
    /// the count via ``isMerge``.
    let parents: [String]
    /// Author name (`%an`).
    let authorName: String
    /// Authored date in ISO-8601 (`%aI`). Parsed once, so the row does not re-parse on every
    /// SwiftUI pass.
    let authoredAt: Date
    /// Commit subject: the first line of the commit message.
    let subject: String

    /// Branch and tag names attached to this commit, in git's own listing order.
    ///
    /// Empty for the common case. `%D` prints something like `HEAD -> main, tag: v1.0.4,
    /// origin/main`; the parser splits on ", " and strips the `HEAD -> ` and `tag: `
    /// prefixes so the sidebar draws just the labels.
    let refNames: [String]

    var id: String { sha }

    /// Whether the commit has two or more parents.
    ///
    /// The list of parents matters to the graph; here the count is enough. A merge in the
    /// sidebar reads differently from a normal commit — even without a lane column.
    var isMerge: Bool { parents.count >= 2 }

    /// Whether this is a root commit (no parents at all).
    ///
    /// Kept separate from ``isMerge`` because "one parent" is the default case and reading it
    /// as `!isMerge && !isRoot` at every call site would be noise.
    var isRoot: Bool { parents.isEmpty }

    /// Parses one record.
    ///
    /// Field order: `sha | shortSHA | parents (space-separated) | authorName | authoredAt |
    /// subject`, `NUL`-delimited. The last field is followed by a trailing `NUL` so the
    /// record ends unambiguously — that trailing byte is *outside* what this function
    /// consumes; ``parseAll(_:)`` is the one that splits on the record boundary.
    ///
    /// - Parameter record: One record's content, without the trailing `NUL`.
    /// - Returns: The parsed line, or `nil` if any required field is missing or malformed.
    ///   Silent nil rather than throwing: `parseAll` treats a bad record as "drop this one
    ///   and continue" so a single corrupt line does not kill the whole page.
    static func parse(_ record: String) -> GitCommitLine? {
        let fields = record.split(separator: "\u{0}", omittingEmptySubsequences: false).map(String.init)
        guard fields.count >= 6 else { return nil }
        let sha = fields[0]
        let shortSHA = fields[1]
        let parents = fields[2].split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        let authorName = fields[3]
        // ISO-strict is what `--date=iso-strict` produces. Foundation's `.iso8601` covers
        // that grammar. Parsing here, not at render time, so `body` never touches the string.
        guard !sha.isEmpty, !shortSHA.isEmpty,
              let authoredAt = Self.iso8601Formatter.date(from: fields[4])
        else { return nil }
        let refNames = Self.parseRefs(fields.count >= 7 ? fields[6] : "")
        return GitCommitLine(
            sha: sha,
            shortSHA: shortSHA,
            parents: parents,
            authorName: authorName,
            authoredAt: authoredAt,
            subject: fields[5],
            refNames: refNames
        )
    }

    /// Extracts ref labels from git's `%D` output.
    ///
    /// - Parameter raw: `HEAD -> main, tag: v1.0.4, origin/main` style string, or empty.
    /// - Returns: `[main, v1.0.4, origin/main]` — the labels that decorate the row.
    static func parseRefs(_ raw: String) -> [String] {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        return trimmed
            .split(separator: ",", omittingEmptySubsequences: true)
            .map { part -> String in
                var name = part.trimmingCharacters(in: .whitespaces)
                // "HEAD -> branch": keep the branch name.
                if let arrow = name.range(of: "HEAD -> ") {
                    name.removeSubrange(name.startIndex..<arrow.upperBound)
                }
                // "tag: v1.2.3": keep the tag name only.
                if name.hasPrefix("tag: ") {
                    name.removeFirst("tag: ".count)
                }
                return name
            }
            .filter { !$0.isEmpty && $0 != "HEAD" }
    }

    /// Parses a page of `git log` output.
    ///
    /// Records inside the output are separated by `\0\n`, but the **last** record ends with
    /// just `\0` — `--pretty=format:` does not add a trailing newline after the final commit.
    /// A naive `split(separator: "\u{0}\n")` loses that last record; verified by asking git
    /// for 200 commits from a repository whose branch has 169, then finding `\0\n` occurs
    /// 168 times, one short.
    ///
    /// The parser splits on the record boundary and only *then* on the field boundary. It
    /// would be tempting to flatten the whole output on `\0` and take six at a time, and an
    /// earlier revision did — but a malformed record with too few `\0`s would then bleed
    /// into the record after it and silently ship a wrong subject. Splitting first on
    /// `\0\n` (with a fallback for the last, newline-less record) keeps a bad record from
    /// misaligning its neighbours.
    ///
    /// Unparseable records are dropped, not thrown, on the assumption that "one bad line"
    /// should not blank the whole tab.
    ///
    /// - Parameter output: Raw stdout from `git log` invoked with
    ///   ``GitHistoryCommand/prettyFormat``.
    /// - Returns: Commit lines, in the order git returned them.
    static func parseAll(_ output: String) -> [GitCommitLine] {
        var lines: [GitCommitLine] = []
        var remaining = output[...]
        while !remaining.isEmpty {
            let boundary = remaining.range(of: "\u{0}\n")
            let recordEnd = boundary?.lowerBound ?? remaining.endIndex
            let record = String(remaining[remaining.startIndex..<recordEnd])
            if let line = parse(record) { lines.append(line) }
            guard let boundary else { break }
            remaining = remaining[boundary.upperBound...]
        }
        return lines
    }

    private static let fieldsPerRecord = 6

    // ISO-strict without fractional seconds is the shape `%aI` returns. Kept private and
    // shared so the parser does not allocate a formatter per record on a page load.
    private static let iso8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}
