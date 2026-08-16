import Foundation

/// Persistent toggle for the line-number ruler in the plain-text file editor.
///
/// Backed by the `fileEditor.lineNumbers` key, shared by the Settings window
/// (`CmuxSettings` catalog), the `~/.config/cmux/cmux.json` parser, the command palette,
/// and ``FilePreviewTextEditor``.
///
/// Defaults to `true` for the same reason as ``FilePreviewSyntaxHighlightSettings``:
/// line numbers are what makes a stack trace or a review comment actionable. The ruler is
/// drawn only while an editor is open, so this does not add permanently visible chrome.
enum FilePreviewLineNumberSettings {
    /// UserDefaults / cmux.json key.
    static let key = "fileEditor.lineNumbers"

    /// Default state: ruler visible.
    static let defaultEnabled = true

    /// Whether the ruler is currently enabled, honoring the stored override
    /// and falling back to ``defaultEnabled``.
    static func isEnabled(defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: key) == nil ? defaultEnabled : defaults.bool(forKey: key)
    }
}
