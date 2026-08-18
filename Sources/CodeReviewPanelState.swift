import Foundation
import SwiftUI

/// Visibility, width, and contents of the dedicated code-review column.
///
/// A fixed column beside the terminal rather than a pane inside the split tree. Panes are
/// the workspace's own layout — splitting one moves the terminal and shrinks it, and every
/// additional file splits again. This column sits between the terminal area and the right
/// sidebar and keeps a single place for reading code, so opening a file never rearranges
/// the session the user is watching.
@MainActor
final class CodeReviewPanelState: ObservableObject {
    /// Whether the column is on screen.
    @Published var isVisible = false

    /// Column width in points.
    @Published var width: CGFloat = CodeReviewPanelState.defaultWidth

    /// The column's own workspace: its split tree, tabs, and surfaces.
    ///
    /// A real ``Workspace`` rather than a bespoke tab list, so the column gets the behavior
    /// the terminal area already has — its tab bar, splitting a pane, opening a browser
    /// beside a file — instead of a second, thinner implementation of all three that would
    /// drift from Bonsplit on every change.
    ///
    /// It boots with ``NewWorkspaceInitialSurface/empty`` because the first surface is
    /// whichever file the user opened, not a terminal the column would immediately close.
    let workspace: Workspace

    init() {
        workspace = Workspace(title: "Code Review", initialSurface: .empty)
        workspace.applySurfaceTabBarButtons(
            CodeReviewPanelState.tabBarButtons,
            sourcePath: nil,
            globalConfigPath: "",
            terminalCommandSourcePaths: [:],
            workspaceCommands: [:]
        )
    }

    /// The column's tab bar: a browser and the two splits, and no new-terminal button.
    ///
    /// The column is where code is read; a terminal opened here would take the space the
    /// file was in. Terminals belong in the terminal area, which has its own button for
    /// them. The two visibility toggles are left out too — the column hides itself from its
    /// own header, and the right sidebar toggles from the terminal tab bar.
    ///
    /// Built with ``CmuxSurfaceTabBarButton/builtIn(_:id:title:icon:tooltip:)`` rather than the
    /// `.newBrowser` / `.splitRight` / `.splitDown` constants: those are *unresolved action
    /// references*, which the config layer turns into built-in actions before handing them to
    /// a workspace. Passing them straight through leaves the action unresolved and the tab bar
    /// renders a question mark for every button.
    private static let tabBarButtons: [CmuxSurfaceTabBarButton] = [
        .builtIn(.newBrowser),
        .builtIn(.splitRight),
        .builtIn(.splitDown)
    ]

    /// Scheme the diff viewer is served on.
    ///
    /// Diffs are identified by this rather than by URL because each render gets a new file
    /// name; see ``showBrowser(url:)``.
    private static let diffViewerScheme = "cmux-diff-viewer"

    static let defaultWidth: CGFloat = 520
    static let minimumWidth: CGFloat = 320
    static let maximumWidth: CGFloat = 1_400

    /// Shows `filePath`, opening the column if needed.
    ///
    /// Re-opening a file already present selects it instead of adding a duplicate, matching
    /// how the pane-based path treats a second request for the same path.
    ///
    /// - Parameter filePath: File to show.
    /// - Returns: The surface showing the file, whether newly opened or already present, or
    ///   `nil` if the column has no pane to open it in. Callers driving UI ignore this; the
    ///   socket needs it to report a surface id, since answering "opened" with a null surface
    ///   would break the contract every other open path honours.
    @discardableResult
    func show(filePath: String) -> (any Panel)? {
        isVisible = true

        if let existing = existingSurface(for: filePath) {
            workspace.focusPanel(existing.id)
            return existing
        }

        // Into the focused pane as another tab, never a split. Splitting on every opened file
        // is what the column exists to avoid; the user splits deliberately, via the tab bar.
        guard let pane = workspace.bonsplitController.focusedPaneId
            ?? workspace.bonsplitController.allPaneIds.first else { return nil }

        // Markdown gets the rendered viewer, everything else the text editor — the same split
        // the pane-based paths make. Opening `.md` in the plain editor here is what made the
        // preview appear "sometimes": it depended on which entry point the file came through.
        if MarkdownPanelFileLinkResolver.isMarkdownPathLike(filePath) {
            return workspace.newMarkdownSurface(inPane: pane, filePath: filePath, focus: true)
        }
        return workspace.newFilePreviewSurface(inPane: pane, filePath: filePath, focus: true)
    }

    /// Opens `url` in the column as a browser surface, reusing one already showing it.
    ///
    /// Used for diffs. They render in a WebView on the `cmux-diff-viewer://` scheme, so the
    /// column hosts them the same way it hosts a file — as another tab, never a split. Opening
    /// each diff by splitting is what fills the terminal area with panes, which is the thing
    /// the column exists to prevent.
    ///
    /// - Parameter url: Diff viewer URL, as produced by the `cmux diff` pipeline.
    /// - Returns: The browser surface, or `nil` when the column has no pane to open it in.
    @discardableResult
    func showBrowser(url: URL) -> BrowserPanel? {
        isVisible = true

        // Matched by scheme, not by exact URL. The CLI writes a fresh
        // `diff-<timestamp>-<random>-viewer.html` on every invocation, so comparing URLs never
        // finds the tab already showing a diff and the column fills with one tab per click.
        // One diff tab, reloaded, is what "open the diff" means here.
        if url.scheme == Self.diffViewerScheme {
            for (panelId, panel) in workspace.panels {
                guard let browser = panel as? BrowserPanel,
                      browser.currentURL?.scheme == Self.diffViewerScheme else { continue }
                workspace.focusPanel(panelId)
                _ = browser.navigate(to: url)
                return browser
            }
        } else {
            for (panelId, panel) in workspace.panels {
                guard let browser = panel as? BrowserPanel else { continue }
                if browser.currentURL == url {
                    workspace.focusPanel(panelId)
                    return browser
                }
            }
        }

        guard let pane = workspace.bonsplitController.focusedPaneId
            ?? workspace.bonsplitController.allPaneIds.first else { return nil }

        // The diff viewer serves its payload over the `cmux-diff-viewer://` scheme from a
        // `.patch` file beside the HTML. Routed through the remote proxy those requests never
        // arrive, and the page loads but renders nothing — which is exactly how it failed:
        // the viewer appeared, ran its loading path, and showed no code. The split path sets
        // the same two flags; creating the surface directly meant they had to be repeated.
        let isDiffViewer = url.scheme == Self.diffViewerScheme
        return workspace.newBrowserSurface(
            inPane: pane,
            url: url,
            focus: true,
            // `hidden`, not `chromeless`: the address bar stays out of the way but the user
            // can still bring it back, which is how the split path behaves.
            chromeVisibility: isDiffViewer ? .hidden : .visible,
            transparentBackground: isDiffViewer,
            bypassRemoteProxy: isDiffViewer
        )
    }

    /// Returns the surface already showing `filePath`, matching either surface kind.
    ///
    /// - Parameter filePath: Path to look for; symlinks are resolved on both sides so the same
    ///   file reached by different routes counts as one.
    /// - Returns: The existing surface, or `nil` when the file is not open.
    private func existingSurface(for filePath: String) -> (any Panel)? {
        let canonical = (filePath as NSString).resolvingSymlinksInPath
        for (_, panel) in workspace.panels {
            let openPath: String?
            switch panel {
            case let preview as FilePreviewPanel: openPath = preview.filePath
            case let markdown as MarkdownPanel: openPath = markdown.filePath
            default: openPath = nil
            }
            guard let openPath else { continue }
            if (openPath as NSString).resolvingSymlinksInPath == canonical { return panel }
        }
        return nil
    }

    /// Toggles visibility, without discarding what is open.
    func toggle() {
        isVisible.toggle()
    }

    /// Clamps `candidate` into the column's allowed range.
    ///
    /// - Parameters:
    ///   - candidate: Requested width.
    ///   - availableWidth: Window width, used to leave room for the terminal.
    /// - Returns: A usable width.
    nonisolated static func clampedWidth(_ candidate: CGFloat, availableWidth: CGFloat) -> CGFloat {
        let ceiling = min(maximumWidth, max(minimumWidth, availableWidth * 0.6))
        return min(max(candidate, minimumWidth), ceiling)
    }
}
