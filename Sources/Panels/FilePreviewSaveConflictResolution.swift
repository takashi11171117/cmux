import Foundation

/// How the user chose to settle a ``FilePreviewSaveConflict``.
enum FilePreviewSaveConflictResolution: Sendable, Equatable {
    /// Discard local edits and take what is on disk.
    case reload

    /// Show the difference before deciding.
    ///
    /// Present in the model but not offered in the UI yet: the existing diff viewer only
    /// serves files from a trusted root with a narrow MIME allowlist, so wiring it up means
    /// writing a `.patch` containing both the on-disk text and the unsaved buffer in
    /// cleartext. That has to be designed before it ships (AFIDE-13).
    case compare

    /// Keep the in-editor version; the next save overwrites disk.
    case keepMine
}
