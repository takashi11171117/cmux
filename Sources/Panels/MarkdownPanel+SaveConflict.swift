import Foundation

extension MarkdownPanel: FilePreviewSaveConflictResolving {
    /// Reloads from disk, discarding unsaved edits.
    func reloadDiscardingLocalEdits() {
        _ = loadTextContent(replacingDirtyContent: true)
    }

    /// Applies the user's choice and clears the banner.
    ///
    /// - Parameter resolution: What the user picked.
    func resolveSaveConflict(_ resolution: FilePreviewSaveConflictResolution) {
        saveConflictCoordinator.resolve(resolution, on: self)
        saveConflict = saveConflictCoordinator.pending
    }
}
