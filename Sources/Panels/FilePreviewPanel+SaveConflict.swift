import Foundation

extension FilePreviewPanel: FilePreviewSaveConflictResolving {
    /// Reloads from disk, discarding unsaved edits.
    ///
    /// Forwards to the existing loader rather than introducing a second read path, so the
    /// reload behaves identically to the one the refresh button already performs.
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
