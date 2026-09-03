import Foundation

/// Turns a multi-line terminal selection into one line for "Copy as Single Line".
///
/// Ghostty already joins *soft*-wrapped rows when it builds a selection string, so a
/// long shell command that merely wrapped at the window edge copies as one line. The
/// breaks this removes are the *hard* ones: full-screen programs such as Claude Code
/// (Ink) wrap their output to the column count with real newlines and indent the
/// continuation rows, so a command pasted from that output runs as several partial
/// commands. No terminal can tell those rows apart from intentional line breaks, which
/// is why this is an explicit action rather than a change to plain Copy.
///
/// ```swift
/// TerminalSingleLineCopy.joined("  ./scripts/reload.sh --tag \n      stage --launch  ")
/// // "./scripts/reload.sh --tag stage --launch"
/// ```
enum TerminalSingleLineCopy {
    /// Joins the lines of `text` with single spaces.
    ///
    /// Each line loses its leading and trailing whitespace (Ink's indentation and the
    /// padding Ghostty may leave at row ends), blank lines are dropped, and the rest are
    /// joined with one space. Lines are split on any Unicode newline, so `\r\n` and
    /// lone `\r` behave like `\n`.
    ///
    /// - Parameter text: The selection as Ghostty returned it.
    /// - Returns: The joined line, or an empty string when nothing but whitespace was
    ///   selected.
    static func joined(_ text: String) -> String {
        text
            .split(omittingEmptySubsequences: true, whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
