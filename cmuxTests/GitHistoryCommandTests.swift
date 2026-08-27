import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

/// Which `git log` command runs for a given page.
///
/// The bug these prevent: `git log --max-count=0` is legal and returns nothing, which makes
/// the mistake at the call site look like "history reached the end" and hides the bug.
@Suite("Git history command")
struct GitHistoryCommandTests {
    @Test("A normal page produces the documented arguments")
    func normalPageArguments() {
        let command = GitHistoryCommand(maxCount: 200, skip: 0)

        #expect(command.arguments == [
            "log",
            "--max-count=200",
            "--skip=0",
            "--pretty=format:\(GitHistoryCommand.prettyFormat)",
            "--date=iso-strict",
        ])
    }

    @Test("The pretty format uses NUL as the field separator")
    func prettyFormatUsesNUL() {
        // Not `|` and not tab: either can appear inside a commit subject and would break
        // parsing. `%x00` is unambiguous.
        #expect(GitHistoryCommand.prettyFormat.contains("%x00"))
        #expect(!GitHistoryCommand.prettyFormat.contains("|"))
    }

    @Test("A non-positive count is clamped to 1, not passed through")
    func zeroCountBecomesOne() {
        // `--max-count=0` returns nothing, which reads as "no more history" at the caller.
        // Clamping keeps the mistake visible rather than silent.
        let command = GitHistoryCommand(maxCount: 0, skip: 10)
        #expect(command.arguments.contains("--max-count=1"))
    }

    @Test("A negative skip is clamped to 0")
    func negativeSkipBecomesZero() {
        let command = GitHistoryCommand(maxCount: 100, skip: -5)
        #expect(command.arguments.contains("--skip=0"))
    }
}
