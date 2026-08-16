import Foundation

/// The minimum a panel must offer for ``FilePreviewSaveConflictCoordinator`` to resolve a conflict.
///
/// Deliberately separate from `FilePreviewTextEditingPanel`, which describes editing only
/// (`textContent`, `attachTextView`, `retryPendingFocus`, `updateTextContent`,
/// `saveTextContent`) and exposes neither `isDirty` nor a reload entry point. Adding to
/// that protocol would widen a contract used purely for text editing.
///
/// ``reloadDiscardingLocalEdits()`` is a return-less alias rather than the existing
/// `loadTextContent(replacingDirtyContent:)` because the two conforming panels disagree on
/// its return type — `Task<Void, Never>` in one, `Task<Void, Never>?` in the other — so it
/// cannot be stated as a single requirement.
@MainActor
protocol FilePreviewSaveConflictResolving: AnyObject {
    /// Whether the editor holds unsaved changes.
    var isDirty: Bool { get }

    /// Replaces the editor's contents with what is on disk, dropping local edits.
    func reloadDiscardingLocalEdits()
}
