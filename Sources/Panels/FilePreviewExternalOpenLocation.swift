import AppKit
import Foundation

/// A file plus the line an external editor should land on.
///
/// Exists because the two halves live in different places: only the text editor knows
/// where the caret is, and only the preferred-editor command path can carry a line number.
/// This value carries the caret across that gap.
///
/// Deliberately an app-target type. `PreferredEditorService` lives in the lower
/// `CmuxWorkspaces` package and cannot import the app, so callers hand it `URL` and `Int?`
/// separately rather than passing this across the boundary.
struct FilePreviewExternalOpenLocation: Sendable, Equatable {
    /// File to open.
    let fileURL: URL

    /// 1-based line, or `nil` when no line is known.
    let line: Int?

    init(fileURL: URL, line: Int?) {
        self.fileURL = fileURL
        self.line = line
    }

    /// Captures the caret position in `textView`.
    ///
    /// Counts newlines directly instead of consulting ``FilePreviewLineIndex``: that index
    /// is only built when the line-number ruler is switched on, and opening in an external
    /// editor must not silently lose the line number because a display setting is off.
    /// The scan is O(offset) and runs once per menu invocation — an explicit user action —
    /// so it stays well inside the editor's 16 MB ceiling.
    ///
    /// - Parameters:
    ///   - fileURL: File the editor shows.
    ///   - textView: View whose selection provides the caret.
    @MainActor
    init(fileURL: URL, caretIn textView: NSTextView) {
        let offset = textView.selectedRange().location
        self.init(
            fileURL: fileURL,
            line: Self.lineNumber(in: textView.string as NSString, atUTF16Offset: offset)
        )
    }

    /// Returns the 1-based line containing `offset`.
    ///
    /// - Parameters:
    ///   - text: Document to scan.
    ///   - offset: UTF-16 offset; values past the end clamp to the last line.
    /// - Returns: 1-based line number.
    static func lineNumber(in text: NSString, atUTF16Offset offset: Int) -> Int {
        let clamped = max(0, min(offset, text.length))
        guard clamped > 0 else { return 1 }

        var line = 1
        var searchRange = NSRange(location: 0, length: clamped)
        while searchRange.length > 0 {
            let found = text.range(of: "\n", options: [.literal], range: searchRange)
            guard found.location != NSNotFound else { break }
            line += 1
            let next = found.location + found.length
            searchRange = NSRange(location: next, length: max(0, clamped - next))
        }
        return line
    }
}
