import Foundation

/// Decides whether a document gets highlighted, and in which language.
///
/// Pure and dependency-free: no `UserDefaults`, no filesystem, no engine. Both the
/// budget and the language table arrive through `init` so tests can drive small
/// thresholds without megabyte fixtures.
///
/// ```swift
/// let policy = FilePreviewHighlightPolicy()
/// policy.decision(path: "/tmp/Main.swift", byteCount: 1_024)  // .highlight(language: "swift")
/// ```
struct FilePreviewHighlightPolicy: Sendable {
    /// Largest document, in UTF-8 bytes, still worth highlighting.
    let maximumHighlightBytes: Int

    /// Extension-to-language resolver.
    let languages: FilePreviewSyntaxLanguage

    /// Creates a policy.
    ///
    /// - Parameters:
    ///   - maximumHighlightBytes: Byte budget. Defaults to
    ///     ``defaultMaximumHighlightBytes``.
    ///   - languages: Language resolver; defaults to the bundled table.
    init(
        maximumHighlightBytes: Int = FilePreviewHighlightPolicy.defaultMaximumHighlightBytes,
        languages: FilePreviewSyntaxLanguage = FilePreviewSyntaxLanguage()
    ) {
        self.maximumHighlightBytes = maximumHighlightBytes
        self.languages = languages
    }

    /// Returns the decision for a document.
    ///
    /// Size is checked first: past the budget the answer is the same whatever the
    /// language, and the point of the check is to avoid the work entirely.
    ///
    /// `byteCount` is the **UTF-8 byte length of the in-memory string**, not the file
    /// size on disk. `FilePreviewPanel` only ever holds the decoded `String` (it may
    /// have been transcoded from UTF-16 or ISO Latin-1), so the on-disk size is not
    /// what the engine would have to walk.
    ///
    /// - Parameters:
    ///   - path: Path whose extension selects the language.
    ///   - byteCount: UTF-8 byte length of the loaded text.
    /// - Returns: Whether to highlight, and why not when skipping.
    func decision(path: String, byteCount: Int) -> FilePreviewHighlightDecision {
        guard byteCount <= maximumHighlightBytes else {
            return .skippedForSize
        }
        guard let language = languages.language(forPath: path) else {
            return .skippedNoLanguage
        }
        return .highlight(language: language)
    }

    /// Default highlight budget, matching the iOS artifact policy.
    ///
    /// Provisional. AFIDE-01 measured 1,132 ms for an 816 KB Swift file, so a document
    /// at this budget could occupy the engine for roughly two seconds. The real value
    /// is settled in AFIDE-07 against measured typing latency; it lives here as a
    /// constant, injectable through `init`, so tightening it never becomes a
    /// settings-key migration.
    static let defaultMaximumHighlightBytes = 1_500_000
}
