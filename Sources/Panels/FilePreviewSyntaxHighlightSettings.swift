import Foundation

/// Persistent toggle for syntax highlighting in the plain-text file editor.
///
/// Backed by the `fileEditor.syntaxHighlight` key, shared by the Settings window
/// (`CmuxSettings` catalog), the `~/.config/cmux/cmux.json` parser, the command palette,
/// and ``FilePreviewTextEditor``.
///
/// Defaults to `true`, unlike its sibling ``FilePreviewWordWrapSettings``. Word wrap
/// defaults off because wrapping is a matter of taste that changes how existing files
/// look; coloring keywords is the point of opening a source file in an editor, and an
/// editor that ships it off by default fails the goal it was added for. Anyone who
/// disagrees turns it off in Settings.
enum FilePreviewSyntaxHighlightSettings {
    /// UserDefaults / cmux.json key.
    static let key = "fileEditor.syntaxHighlight"

    /// Default state: highlighting on.
    static let defaultEnabled = true

    /// Whether highlighting is currently enabled, honoring the stored override
    /// and falling back to ``defaultEnabled``.
    static func isEnabled(defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: key) == nil ? defaultEnabled : defaults.bool(forKey: key)
    }
}
