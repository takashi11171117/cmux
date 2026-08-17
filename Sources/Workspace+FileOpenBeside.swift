import CmuxSettings
import Foundation

extension Workspace {
    /// Opens `filePath` beside `sourcePanelId` instead of on top of it.
    ///
    /// Reuses a pane to the right of the source when one exists, and splits one into being
    /// otherwise — the behavior the file explorer and terminal Cmd-click already get through
    /// ``openOrFocusFilePreviewSplit(from:filePath:)``.
    ///
    /// This exists so the socket's `file.open` can share that behavior. `cmux open` is
    /// typically run from the terminal the user is watching; opening the file as another tab
    /// in that same pane hides the session that asked for it.
    ///
    /// Markdown routes to the rendered viewer, matching `CommandClickFileOpenRouter`, so all
    /// three entry points agree on which panel type a path becomes.
    ///
    /// - Parameters:
    ///   - sourcePanelId: Panel the request came from; the new surface opens to its right.
    ///   - filePath: File to open.
    ///   - defaults: Settings store deciding markdown routing.
    /// - Returns: The opened panel, or `nil` when neither route could place it.
    @MainActor
    func openFileBesideSource(
        from sourcePanelId: UUID,
        filePath: String,
        defaults: UserDefaults = .standard
    ) -> (any Panel)? {
        let store = FileRouteSettingsStore(defaults: defaults)
        let routesToMarkdown = store.shouldRouteMarkdown(path: filePath)

        // Opening a file moves focus onto it, so the *next* open would otherwise treat that
        // file panel as its source and split again to its right — one new pane per file.
        // When focus already sits on a file surface, reuse that pane as tabs instead. The
        // result is a single review pane that accumulates tabs, not a shrinking row of panes.
        if let focused = panels[sourcePanelId],
           focused is FilePreviewPanel || focused is MarkdownPanel,
           let hostPane = paneId(forPanelId: sourcePanelId) {
            if routesToMarkdown {
                return newMarkdownSurface(inPane: hostPane, filePath: filePath, focus: true)
            }
            return newFilePreviewSurface(inPane: hostPane, filePath: filePath, focus: true)
        }

        if routesToMarkdown,
           let markdown = openOrFocusMarkdownSplit(from: sourcePanelId, filePath: filePath) {
            return markdown
        }
        return openOrFocusFilePreviewSplit(from: sourcePanelId, filePath: filePath)
    }
}
