import Foundation

/// Seam between the editor and whichever engine produces syntax highlighting.
///
/// The concrete engine (highlight.js evaluated in JavaScriptCore, or a hand-written
/// scanner) sits behind this protocol so that choosing or replacing it never changes
/// ``FilePreviewSyntaxHighlightController`` or anything above it.
///
/// ## Coordinate contract
///
/// Both the implementation and the caller must follow this exactly; getting it wrong
/// paints attributes at the wrong offsets, which looks like a rendering bug rather
/// than a coordinate bug.
///
/// - `text` is the **entire document**. Never pass a slice.
/// - `range` is the region that needs color *now*, expressed in **full-document
///   UTF-16 offsets**.
/// - Returned ``FilePreviewHighlightRun/range`` values are likewise in
///   **full-document UTF-16 offsets**.
/// - Returning runs outside `range` is allowed; the caller clips them.
///
/// The document is passed whole because a block comment or multi-line string can
/// *open* before `range` begins. An engine handed only the visible slice would read
/// that region as ordinary code. `String` is copy-on-write, so passing the whole
/// document costs no copy.
///
/// Restricting `range` is therefore about how much the caller must transfer and
/// apply, not necessarily about how much the engine scans: highlight.js walks the
/// full text regardless (measured in AFIDE-01).
///
/// ## Failure
///
/// Deliberately not `throws`. An engine that fails, times out, or does not know the
/// language returns an empty array, which renders as plain text — the same state as
/// an unsupported extension. Text is always displayed and editable.
protocol FilePreviewSyntaxHighlighting: Sendable {
    /// Returns the runs intersecting `range`, in full-document UTF-16 offsets.
    ///
    /// - Parameters:
    ///   - text: The entire document.
    ///   - language: Engine language identifier from ``FilePreviewSyntaxLanguage``.
    ///   - range: Region needing color now, in full-document UTF-16 offsets.
    /// - Returns: Runs in full-document coordinates; empty when nothing can be produced.
    func runs(for text: String, language: String, range: NSRange) async -> [FilePreviewHighlightRun]
}
