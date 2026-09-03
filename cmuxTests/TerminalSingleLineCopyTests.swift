import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

/// "Copy as Single Line" on a terminal selection.
///
/// The motivating input is a command Claude Code printed: Ink hard-wraps it to the
/// column count and indents the continuation rows, so plain Copy yields several lines
/// that a shell would run one by one.
@Suite("Terminal single-line copy")
struct TerminalSingleLineCopyTests {
    @Test("Hard-wrapped, indented rows join into one command")
    func joinsIndentedContinuationRows() {
        // Two rows as Ghostty hands them over: the first ends where Ink wrapped it, the
        // second carries Ink's continuation indent.
        let selection = "  ./scripts/reload.sh --tag stage \n      --launch --verbose"
        #expect(TerminalSingleLineCopy.joined(selection) == "./scripts/reload.sh --tag stage --launch --verbose")
    }

    @Test("Trailing row padding and blank rows are dropped")
    func dropsPaddingAndBlankRows() {
        let selection = "git commit -m \"a\"   \n\n   \n    && git push   \n"
        #expect(TerminalSingleLineCopy.joined(selection) == "git commit -m \"a\" && git push")
    }

    @Test("CRLF and lone CR count as line breaks")
    func treatsAllNewlineFormsAlike() {
        #expect(TerminalSingleLineCopy.joined("one\r\ntwo\rthree\nfour") == "one two three four")
    }

    @Test("A single line only loses its surrounding whitespace")
    func singleLineIsTrimmed() {
        #expect(TerminalSingleLineCopy.joined("   ls -la   ") == "ls -la")
    }

    @Test("Whitespace-only selections become empty so the caller can decline to copy")
    func whitespaceOnlyBecomesEmpty() {
        #expect(TerminalSingleLineCopy.joined(" \n\t\n ").isEmpty)
    }

    @Test("Interior spacing inside a row is preserved")
    func keepsInteriorSpacing() {
        // Only row edges are trimmed; the two spaces inside stay, since collapsing them
        // could change quoted arguments.
        #expect(TerminalSingleLineCopy.joined("echo  \"a  b\"\n  | cat") == "echo  \"a  b\" | cat")
    }
}
