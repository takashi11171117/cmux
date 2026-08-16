import Foundation

/// Outcome of asking whether a document should be highlighted at all.
///
/// Produced by ``FilePreviewHighlightPolicy/decision(path:byteCount:)`` before the
/// engine is ever constructed, so a skip costs nothing.
enum FilePreviewHighlightDecision: Sendable, Equatable {
    /// Highlight using this engine language id.
    case highlight(language: String)

    /// Document exceeds the highlight byte budget; render plain text.
    ///
    /// Distinct from ``skippedNoLanguage`` so tests can prove *why* a document was
    /// skipped. Both render identically.
    case skippedForSize

    /// Extension maps to no known grammar; render plain text.
    case skippedNoLanguage
}
