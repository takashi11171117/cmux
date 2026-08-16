import AppKit
import Foundation

/// Maps a ``FilePreviewTokenRole`` to a drawing color for one editor background.
///
/// Colors are lifted from the two highlight.js themes already shipping in the app
/// bundle for Markdown preview — `Resources/markdown-viewer/highlight-github.css` and
/// `highlight-github-dark.css` — so a code file and a Markdown fenced block are tinted
/// the same way.
///
/// The engine never sees these colors, and this type never sees the engine. That
/// split is what makes a theme change a palette swap plus a repaint, with no
/// re-tokenization.
///
/// ```swift
/// let palette = FilePreviewHighlightPalette(background: .textBackgroundColor, foreground: .textColor)
/// let color = palette.color(for: .keyword)
/// ```
struct FilePreviewHighlightPalette {
    /// Background the palette was resolved against.
    let background: NSColor

    /// Whether the dark variant was selected.
    let isDark: Bool

    private let colorsByRole: [FilePreviewTokenRole: NSColor]

    /// Builds the palette for one editor theme, picking the light or dark variant.
    ///
    /// Selection uses WCAG relative luminance against `0.179`, the point where black
    /// and white text achieve equal contrast, rather than a naive `0.5` on raw
    /// channel values.
    ///
    /// ``FilePreviewTokenRole/plain`` is taken from `foreground` rather than from the
    /// theme file. Unclassified text is the majority of any document, and it should stay
    /// exactly the color the editor would have drawn without highlighting — otherwise
    /// enabling highlighting silently restyles ordinary prose, and the two code paths
    /// (highlighted and not) disagree about what "body text" looks like.
    ///
    /// - Note: Both source themes assume their own background (`#ffffff` / `#0d1117`).
    ///   The editor's `themeBackgroundColor` can be any color, so a mid-luminance
    ///   custom theme may land near the fence and get a variant tuned for a more
    ///   extreme background. ``contrastRatio(for:)`` exists to detect that case.
    ///
    /// - Parameters:
    ///   - background: Editor background the text will be drawn on.
    ///   - foreground: Editor body color, used for ``FilePreviewTokenRole/plain``.
    init(background: NSColor, foreground: NSColor) {
        let dark = Self.relativeLuminance(of: background) < 0.179
        self.background = background
        self.isDark = dark
        var colors = dark ? Self.darkColors : Self.lightColors
        colors[.plain] = foreground
        self.colorsByRole = colors
    }

    /// Returns the color for `role` under this palette's background.
    ///
    /// - Parameter role: Semantic role produced by the engine.
    /// - Returns: Color to apply as `.foregroundColor`.
    func color(for role: FilePreviewTokenRole) -> NSColor {
        colorsByRole[role] ?? colorsByRole[.plain] ?? .textColor
    }

    /// Returns the WCAG contrast ratio between `role`'s color and the background.
    ///
    /// Ranges from `1.0` (identical) to `21.0` (black on white). WCAG AA for body text
    /// is `4.5`. Used by tests to prove every role stays legible on both variants
    /// instead of relying on someone eyeballing a screenshot.
    ///
    /// - Parameter role: Role to measure.
    /// - Returns: Contrast ratio, larger is more legible.
    func contrastRatio(for role: FilePreviewTokenRole) -> Double {
        let foreground = Self.relativeLuminance(of: color(for: role))
        let backdrop = Self.relativeLuminance(of: background)
        let lighter = max(foreground, backdrop)
        let darker = min(foreground, backdrop)
        return (lighter + 0.05) / (darker + 0.05)
    }

    /// Returns WCAG relative luminance for `color`, or `0` if it has no sRGB form.
    ///
    /// - Parameter color: Color to measure.
    /// - Returns: Luminance in `0...1`.
    static func relativeLuminance(of color: NSColor) -> Double {
        guard let srgb = color.usingColorSpace(.sRGB) else { return 0 }
        let red = linearized(srgb.redComponent)
        let green = linearized(srgb.greenComponent)
        let blue = linearized(srgb.blueComponent)
        return 0.2126 * red + 0.7152 * green + 0.0722 * blue
    }

    /// Undoes sRGB gamma encoding for one channel.
    private static func linearized(_ component: CGFloat) -> Double {
        let value = Double(component)
        return value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
    }

    /// Builds an opaque sRGB color from a `0xRRGGBB` literal.
    private static func srgb(_ hex: UInt32) -> NSColor {
        NSColor(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255.0,
            green: CGFloat((hex >> 8) & 0xFF) / 255.0,
            blue: CGFloat(hex & 0xFF) / 255.0,
            alpha: 1.0
        )
    }

    /// github light theme, from `Resources/markdown-viewer/highlight-github.css`.
    ///
    /// ``FilePreviewTokenRole/number`` and ``FilePreviewTokenRole/attribute`` share a
    /// color in both variants. That is faithful to the source: the CSS puts
    /// `.hljs-number` and `.hljs-attr` in one selector group. Seven roles therefore
    /// render in six colors. `.hljs-built_in` (`#e36209` / `#ffa657`) is the obvious
    /// seventh, but it is reserved for built-in types, which map to
    /// ``FilePreviewTokenRole/type``; spending it on attributes would make a built-in
    /// type and an attribute swap appearances. Kept faithful pending dogfood.
    private static let lightColors: [FilePreviewTokenRole: NSColor] = [
        .plain: srgb(0x24292E),      // .hljs — fallback only; init overrides with the theme's foreground
        .keyword: srgb(0xD73A49),    // .hljs-keyword
        .string: srgb(0x032F62),     // .hljs-string
        .comment: srgb(0x6A737D),    // .hljs-comment
        .number: srgb(0x005CC5),     // .hljs-number
        .type: srgb(0x6F42C1),       // .hljs-title
        .attribute: srgb(0x005CC5),  // .hljs-attr
    ]

    /// github-dark theme, from `Resources/markdown-viewer/highlight-github-dark.css`.
    private static let darkColors: [FilePreviewTokenRole: NSColor] = [
        .plain: srgb(0xC9D1D9),      // fallback only; init overrides with the theme's foreground
        .keyword: srgb(0xFF7B72),
        .string: srgb(0xA5D6FF),
        .comment: srgb(0x8B949E),
        .number: srgb(0x79C0FF),
        .type: srgb(0xD2A8FF),
        .attribute: srgb(0x79C0FF),
    ]
}
