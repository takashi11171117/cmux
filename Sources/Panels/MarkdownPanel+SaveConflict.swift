import Foundation

extension MarkdownPanel: FilePreviewSaveConflictResolving {
    /// Reloads from disk, discarding unsaved edits.
    func reloadDiscardingLocalEdits() {
        _ = loadTextContent(replacingDirtyContent: true)
    }

    /// Drops any pending conflict, for when the file stops existing.
    func clearSaveConflict() {
        guard saveConflict != nil else { return }
        saveConflictCoordinator.clear()
        saveConflict = nil
    }

    /// Applies the user's choice and clears the banner.
    ///
    /// - Parameter resolution: What the user picked.
    func resolveSaveConflict(_ resolution: FilePreviewSaveConflictResolution) {
        saveConflictCoordinator.resolve(resolution, on: self)
        saveConflict = saveConflictCoordinator.pending
    }
}
