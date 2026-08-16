import Foundation

/// One unresolved collision between unsaved edits and a newer version on disk.
///
/// Created when a file changes underneath an editor that has unsaved work — routinely, in
/// this app, because an agent rewrote the file the user was editing.
struct FilePreviewSaveConflict: Sendable, Equatable {
    /// Path of the file that changed.
    let filePath: String

    /// Contents now on disk.
    ///
    /// Captured at detection time so resolving does not need another read, and so the
    /// choice offered reflects what was actually seen.
    let diskContent: String

    /// When the collision was noticed.
    let detectedAt: Date

    init(filePath: String, diskContent: String, detectedAt: Date) {
        self.filePath = filePath
        self.diskContent = diskContent
        self.detectedAt = detectedAt
    }
}
