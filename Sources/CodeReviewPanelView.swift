import AppKit
import CmuxAppKitSupportUI
import SwiftUI

/// The code-review column: the column's own workspace, filling the column.
///
/// The body is ``WorkspaceContentView`` driving ``CodeReviewPanelState/workspace``, so the
/// column behaves like the terminal area — the same tab bar and its buttons, splitting a
/// pane, opening a browser beside a file — rather than reimplementing those on a bespoke
/// container.
///
/// It carries no chrome of its own. Hiding the column is the `</>` button in the titlebar,
/// which is outside the column and so survives it being hidden; a second hide button here
/// only collided with that one once the column reached the window's trailing edge.
struct CodeReviewPanelView: View {
    @ObservedObject var state: CodeReviewPanelState
    let windowAppearance: WindowAppearanceSnapshot
    let isFullScreen: Bool
    let isVisibleInUI: Bool

    var body: some View {
        VStack(spacing: 0) {
            WorkspaceContentView(
                workspace: state.workspace,
                isWorkspaceVisible: isVisibleInUI,
                isWorkspaceInputActive: true,
                rightSidebarOwnsInputFocus: false,
                isFullScreen: isFullScreen,
                workspacePortalPriority: CodeReviewPanelView.portalPriority,
                windowAppearance: windowAppearance,
                onThemeRefreshRequest: nil
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Matches what the terminal area gives its selected workspace.
    ///
    /// Not a higher number: portals are window-level AppKit layers, so raising this above the
    /// rest puts the column's surfaces over the whole window — including this view's own hide
    /// button and the column's resize handle, which then cannot be clicked at all.
    private static let portalPriority = 2
}
