import SwiftUI

/// Non-modal bar offering a way out when disk and the editor disagree.
///
/// Not a sheet. cmux runs several agent sessions at once, and a modal would freeze the
/// whole window over one file's collision. A sheet also makes the "another change arrives
/// while the prompt is up" case awkward, whereas a banner just re-renders.
///
/// Appears only while a conflict is pending, so it adds no permanent chrome.
struct FilePreviewSaveConflictBanner: View {
    /// Conflict being offered for resolution.
    let conflict: FilePreviewSaveConflict

    /// Invoked with the user's choice.
    let onResolve: (FilePreviewSaveConflictResolution) -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text(String(localized: "filePreview.saveConflict.title", defaultValue: "This file changed on disk"))
                    .font(.system(size: 12, weight: .semibold))
                Text(String(localized: "filePreview.saveConflict.message", defaultValue: "You have unsaved edits. Choose how to continue."))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Button(String(localized: "filePreview.saveConflict.keepMine", defaultValue: "Keep Mine")) {
                onResolve(.keepMine)
            }
            .controlSize(.small)

            Button(String(localized: "filePreview.saveConflict.reload", defaultValue: "Reload")) {
                onResolve(.reload)
            }
            .controlSize(.small)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.orange.opacity(0.12))
        .accessibilityIdentifier("FilePreviewSaveConflictBanner")
    }
}
