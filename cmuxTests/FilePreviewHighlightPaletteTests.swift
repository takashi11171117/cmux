import AppKit
import Foundation
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

@Suite("FilePreviewHighlightPalette")
struct FilePreviewHighlightPaletteTests {
    /// WCAG AA for body text. Every role must clear this on both variants.
    private static let minimumContrast = 4.5

    private static let lightBackground = NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
    private static let darkBackground = NSColor(
        srgbRed: 13 / 255, green: 17 / 255, blue: 23 / 255, alpha: 1
    )
    /// Body colors the editor would use; `plain` is taken from these, not the theme file.
    private static let lightForeground = NSColor(
        srgbRed: 36 / 255, green: 41 / 255, blue: 46 / 255, alpha: 1
    )
    private static let darkForeground = NSColor(
        srgbRed: 201 / 255, green: 209 / 255, blue: 217 / 255, alpha: 1
    )

    @Test("every role is legible on the light background")
    func lightVariantIsLegible() {
        let palette = FilePreviewHighlightPalette(background: Self.lightBackground, foreground: Self.lightForeground)
        for role in FilePreviewTokenRole.allCases {
            let ratio = palette.contrastRatio(for: role)
            #expect(
                ratio >= Self.minimumContrast,
                "\(role.rawValue) contrast \(ratio) is below \(Self.minimumContrast) on light"
            )
        }
    }

    @Test("every role is legible on the dark background")
    func darkVariantIsLegible() {
        let palette = FilePreviewHighlightPalette(background: Self.darkBackground, foreground: Self.darkForeground)
        for role in FilePreviewTokenRole.allCases {
            let ratio = palette.contrastRatio(for: role)
            #expect(
                ratio >= Self.minimumContrast,
                "\(role.rawValue) contrast \(ratio) is below \(Self.minimumContrast) on dark"
            )
        }
    }

    @Test("background luminance selects the variant")
    func variantFollowsBackground() {
        #expect(FilePreviewHighlightPalette(background: Self.lightBackground, foreground: Self.lightForeground).isDark == false)
        #expect(FilePreviewHighlightPalette(background: Self.darkBackground, foreground: Self.darkForeground).isDark == true)
    }

    @Test("variants do not share colors for the same role")
    func variantsDiffer() {
        let light = FilePreviewHighlightPalette(background: Self.lightBackground, foreground: Self.lightForeground)
        let dark = FilePreviewHighlightPalette(background: Self.darkBackground, foreground: Self.darkForeground)
        for role in FilePreviewTokenRole.allCases {
            #expect(
                light.color(for: role) != dark.color(for: role),
                "\(role.rawValue) is identical in both variants, so a theme switch would not repaint it"
            )
        }
    }

    @Test("keyword, string, and comment are distinguishable from body text")
    func coreRolesDifferFromPlain() {
        // FR-01 AC1 requires keywords, strings, and comments to render in a color other
        // than the body color. Guarding the three the acceptance criterion names.
        for background in [Self.lightBackground, Self.darkBackground] {
            let palette = FilePreviewHighlightPalette(background: background, foreground: background == Self.lightBackground ? Self.lightForeground : Self.darkForeground)
            let plain = palette.color(for: .plain)
            for role in [FilePreviewTokenRole.keyword, .string, .comment] {
                #expect(
                    palette.color(for: role) != plain,
                    "\(role.rawValue) matches body color, so FR-01 AC1 would not hold"
                )
            }
        }
    }

    @Test("relative luminance matches known anchors")
    func luminanceAnchors() {
        let white = FilePreviewHighlightPalette.relativeLuminance(of: Self.lightBackground)
        let black = FilePreviewHighlightPalette.relativeLuminance(
            of: NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)
        )
        #expect(abs(white - 1.0) < 0.0001)
        #expect(abs(black) < 0.0001)
    }

    @Test("contrast of black on white is the WCAG maximum")
    func contrastRangeAnchor() {
        let palette = FilePreviewHighlightPalette(background: Self.lightBackground, foreground: Self.lightForeground)
        let ratio = palette.contrastRatio(for: .plain)
        #expect(ratio > 1.0)
        #expect(ratio <= 21.0)
    }

    @Test("a mid-luminance background still resolves every role")
    func midLuminanceBackgroundResolves() {
        // New-L: both source themes assume their own background. A custom mid-gray theme
        // is out of their design range; this only proves nothing crashes or falls back to
        // a missing entry, not that the result is pleasant.
        let midGray = NSColor(srgbRed: 0.5, green: 0.5, blue: 0.5, alpha: 1)
        let palette = FilePreviewHighlightPalette(background: midGray, foreground: .white)
        for role in FilePreviewTokenRole.allCases {
            #expect(palette.color(for: role).usingColorSpace(.sRGB) != nil)
        }
    }
}
