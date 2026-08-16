import Foundation

/// Semantic classification of one highlighted token, carrying no color.
///
/// The highlight engine returns roles instead of colors so that the engine and the
/// theme stay independent: ``FilePreviewHighlightPalette`` resolves a role to an
/// `NSColor` from the editor's current background, so swapping the engine never
/// touches the theme and swapping the theme never touches the engine.
///
/// The case list is deliberately coarse. highlight.js emits dozens of scope names
/// (`title.class.inherited`, `selector-pseudo`, `template-variable`); they collapse
/// into these seven so the palette stays small enough to verify for contrast.
enum FilePreviewTokenRole: String, Sendable, CaseIterable {
    /// Language keywords (`func`, `if`, `return`) and language-level variables (`self`).
    case keyword

    /// String and character literals, interpolation segments, and regular expressions.
    case string

    /// Line comments, block comments, doc comments, and quoted blocks.
    case comment

    /// Numeric literals and language literals such as `true`, `false`, `nil`.
    case number

    /// Type names, declaration titles, and built-in types.
    case type

    /// Attributes, annotations, metadata, and selector fragments.
    case attribute

    /// Text the engine did not classify; drawn in the editor's body color.
    ///
    /// Also the fallback the controller paints across the whole document before
    /// overlaying visible-range runs, so off-screen text is never left at
    /// `NSTextView`'s default black on a dark theme.
    case plain
}
