import Foundation

/// Holds the pending save conflict for one panel and applies the user's choice.
///
/// ## Why it observes rather than intercepts
///
/// The natural-looking design — notice the change in `handleObservedFileChange()` and skip
/// the reload while dirty — does not work here, for three reasons found in the existing code:
///
/// 1. Nothing has read the file at that point, so there is no disk content to show.
/// 2. Skipping the reload also skips the dirty branch's bookkeeping (`originalTextContent`,
///    the tab's dirty marker, `isFileUnavailable`), so the tab would disagree with disk and
///    the file-deleted fallback would stop working.
/// 3. That method is also called from the save-failure path, which would raise a conflict
///    banner when nothing external had changed.
///
/// So the reload proceeds untouched and this type is told afterward, from inside the branch
/// that already has both versions in hand. No extra I/O, and the pre-existing behavior — the
/// buffer is preserved — is unchanged; the only difference is that the user is now asked.
@MainActor
final class FilePreviewSaveConflictCoordinator {
    /// The conflict awaiting a decision, if any.
    private(set) var pending: FilePreviewSaveConflict?

    init() {}

    /// Records a conflict discovered while the editor was dirty.
    ///
    /// The caller passes raw values and holds no policy; every condition lives here so the
    /// two call sites stay two lines each.
    ///
    /// - Parameters:
    ///   - filePath: File that changed.
    ///   - diskContent: Contents just read from disk.
    ///   - previousDiskContent: Contents believed to be on disk before this read.
    ///   - bufferContent: What the editor currently shows.
    ///   - now: Detection timestamp; injected so tests are not time-dependent.
    func noteDiskContentWhileDirty(
        filePath: String,
        diskContent: String,
        previousDiskContent: String,
        bufferContent: String,
        now: Date = Date()
    ) {
        // Disk is unchanged: this is a re-read, not a collision. Also what keeps the
        // save-failure path from raising a banner, since a failed write leaves disk as it was.
        guard diskContent != previousDiskContent else { return }

        // The editor already shows exactly what is on disk — typically our own save coming
        // back through the watcher. Defined without consulting `isSaving` on purpose:
        // FilePreviewPanel guards its watcher with it and MarkdownPanel does not, and that
        // asymmetry is real, so the condition cannot depend on it.
        guard bufferContent != diskContent else { return }

        // Latest-wins rather than a queue: one panel edits one file, so an older conflict
        // describes a version nobody can act on anymore. The buffer is never touched, which
        // is what keeps repeated external changes from losing the user's work.
        pending = FilePreviewSaveConflict(
            filePath: filePath, diskContent: diskContent, detectedAt: now
        )
    }

    /// Applies `resolution` to `panel` and clears the pending conflict.
    ///
    /// - Parameters:
    ///   - resolution: The user's choice.
    ///   - panel: Panel to act on.
    func resolve(
        _ resolution: FilePreviewSaveConflictResolution,
        on panel: any FilePreviewSaveConflictResolving
    ) {
        switch resolution {
        case .reload:
            panel.reloadDiscardingLocalEdits()
            pending = nil
        case .keepMine:
            // Deliberately touches nothing: the buffer already holds the user's version, and
            // the next save writes it. Dismissing is the whole action.
            pending = nil
        case .compare:
            // Left pending until AFIDE-13 settles how to show the difference; clearing it
            // here would silently drop the conflict.
            break
        }
    }

    /// Drops any pending conflict, for when the file stops existing.
    func clear() {
        pending = nil
    }
}
