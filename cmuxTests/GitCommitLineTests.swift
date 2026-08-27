import Foundation
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

/// What the parser reads out of `git log` output.
///
/// The bugs these prevent: (1) treating "one bad line" as fatal, which would blank the whole
/// page for a single malformed commit; (2) letting subject contents that happen to contain
/// tab or `|` — plausible in real commits — break parsing; (3) confusing a merge (multiple
/// parents) with a normal commit at read time, before the graph layout even runs.
@Suite("Git commit line")
struct GitCommitLineTests {
    private static let separator = "\u{0}"

    private func record(
        sha: String = "a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0",
        shortSHA: String = "a1b2c3d",
        parents: String = "b0a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9",
        author: String = "Taro Yamada",
        date: String = "2026-08-27T10:15:30+09:00",
        subject: String
    ) -> String {
        [sha, shortSHA, parents, author, date, subject].joined(separator: Self.separator)
    }

    @Test("A normal commit parses every field")
    func parsesNormalCommit() {
        let line = GitCommitLine.parse(record(subject: "feat: add history sidebar"))

        #expect(line?.sha.hasPrefix("a1b2c3d4") == true)
        #expect(line?.shortSHA == "a1b2c3d")
        #expect(line?.parents.count == 1)
        #expect(line?.authorName == "Taro Yamada")
        #expect(line?.subject == "feat: add history sidebar")
        #expect(line?.isMerge == false)
        #expect(line?.isRoot == false)
    }

    @Test("A merge commit has two or more parents")
    func mergeCommitHasTwoParents() {
        let mergeParents = "b0a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9 c0d1e2f3a4b5c6d7e8f9a0b1c2d3e4f5a6b7c8d9"
        let line = GitCommitLine.parse(record(parents: mergeParents, subject: "Merge branch 'x'"))

        #expect(line?.parents.count == 2)
        #expect(line?.isMerge == true)
        #expect(line?.isRoot == false)
    }

    @Test("A root commit has no parents")
    func rootCommitHasNoParents() {
        let line = GitCommitLine.parse(record(parents: "", subject: "Initial commit"))

        #expect(line?.parents.isEmpty == true)
        #expect(line?.isRoot == true)
        #expect(line?.isMerge == false)
    }

    @Test("A subject containing a tab is preserved as-is")
    func subjectWithTabIsPreserved() {
        // Real commit messages contain tabs. Splitting on tab would truncate the subject.
        let line = GitCommitLine.parse(record(subject: "fix: split\ton tab"))

        #expect(line?.subject == "fix: split\ton tab")
    }

    @Test("A subject containing a pipe is preserved as-is")
    func subjectWithPipeIsPreserved() {
        // Same story for `|`, which was the naive first delimiter choice.
        let line = GitCommitLine.parse(record(subject: "chore: shell | pipeline"))

        #expect(line?.subject == "chore: shell | pipeline")
    }

    @Test("A malformed record is dropped, not parsed as garbage")
    func malformedRecordIsDropped() {
        // Missing fields: the parser must reject rather than fill with empty strings, or a
        // row rendered from this would look plausible and click into nothing.
        #expect(GitCommitLine.parse("only\u{0}three\u{0}fields") == nil)
    }

    @Test("A bad date rejects the whole record")
    func badDateRejectsRecord() {
        let broken = record(date: "not-a-date", subject: "irrelevant")

        // If the date could not be parsed, the row cannot show "2 hours ago". Rejecting the
        // whole record is preferable to guessing a date.
        #expect(GitCommitLine.parse(broken) == nil)
    }

    @Test("parseAll drops the trailing empty record after the last NUL")
    func parseAllDropsTrailingEmpty() {
        // `git log --pretty=format:...%x00` ends every record with a NUL, including the last
        // one — the naive split would then yield one empty trailing element. Losing that
        // silently is expected; keeping it would show up as a mysterious blank row.
        let one = record(subject: "one")
        let two = record(subject: "two")
        let output = one + "\u{0}\n" + two + "\u{0}\n"

        let lines = GitCommitLine.parseAll(output)

        #expect(lines.count == 2)
        #expect(lines.map(\.subject) == ["one", "two"])
    }

    @Test("parseAll drops a bad record but keeps its neighbours")
    func parseAllSurvivesOneBadRecord() {
        // Otherwise a single corrupted line kills the whole page, which is the wrong tradeoff
        // when the alternative is "show every commit that parsed".
        let good = record(subject: "good")
        let bad = "malformed"
        let output = good + "\u{0}\n" + bad + "\u{0}\n"

        let lines = GitCommitLine.parseAll(output)

        #expect(lines.map(\.subject) == ["good"])
    }

    @Test("The last record without a trailing newline is not lost")
    func lastRecordWithoutTrailingNewlineIsKept() {
        // git log --pretty=format: does not add a trailing newline after the final commit.
        // Splitting on "\u{0}\n" as if every record were newline-terminated drops the last
        // one; measured on cmux itself, asking for 200 commits from a 169-commit branch
        // produced 168 records under the naive splitter.
        let a = record(subject: "first")
        let b = record(subject: "last")
        let output = a + "\u{0}\n" + b + "\u{0}"

        let lines = GitCommitLine.parseAll(output)

        #expect(lines.map(\.subject) == ["first", "last"])
    }
}
