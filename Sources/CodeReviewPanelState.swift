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
    private static let tabBarButtons: [CmuxSurfaceTabBarButton] = [
        .newBrowser,
        .splitRight,
        .splitDown
    ]

    static let defaultWidth: CGFloat = 520
    static let minimumWidth: CGFloat = 320
    static let maximumWidth: CGFloat = 1_400

    /// Shows `filePath`, opening the column if needed.
    ///
    /// Re-opening a file already present selects it instead of adding a duplicate, matching
    /// how the pane-based path treats a second request for the same path.
    ///
    /// - Parameter filePath: File to show.
    func show(filePath: String) {
        isVisible = true

        let canonical = (filePath as NSString).resolvingSymlinksInPath
        for (panelId, panel) in workspace.panels {
            guard let preview = panel as? FilePreviewPanel else { continue }
            if (preview.filePath as NSString).resolvingSymlinksInPath == canonical {
                workspace.focusPanel(panelId)
                return
            }
        }

        // Into the focused pane as another tab, never a split. Splitting on every opened file
        // is what the column exists to avoid; the user splits deliberately, via the tab bar.
        guard let pane = workspace.bonsplitController.focusedPaneId
            ?? workspace.bonsplitController.allPaneIds.first else { return }
        _ = workspace.newFilePreviewSurface(inPane: pane, filePath: filePath, focus: true)
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
    static func clampedWidth(_ candidate: CGFloat, availableWidth: CGFloat) -> CGFloat {
        let ceiling = min(maximumWidth, max(minimumWidth, availableWidth * 0.6))
        return min(max(candidate, minimumWidth), ceiling)
    }
}
