import Foundation

/// One contiguous span of text that carries a single ``FilePreviewTokenRole``.
///
/// Colorless by design: the engine produces runs, ``FilePreviewHighlightPalette``
/// turns a run's role into an `NSColor`, and the controller applies it. Keeping
/// color out of this type is what lets the same run survive a theme change.
///
/// ```swift
/// let run = FilePreviewHighlightRun(range: NSRange(location: 0, length: 6), role: .keyword)
/// ```
struct FilePreviewHighlightRun: Sendable, Equatable {
    /// UTF-16 range **in the full document**, never relative to a slice.
    ///
    /// Producers and consumers share one coordinate space; see
    /// ``FilePreviewSyntaxHighlighting/runs(for:language:range:)`` for the contract.
    let range: NSRange

    /// What the span means, independent of how it is colored.
    let role: FilePreviewTokenRole

    init(range: NSRange, role: FilePreviewTokenRole) {
        self.range = range
        self.role = role
    }
}
