import AppKit
import CmuxAppKitSupportUI
import SwiftUI

/// The code-review column: the column's own workspace, under a thin header.
///
/// The body is ``WorkspaceContentView`` driving ``CodeReviewPanelState/workspace``, so the
/// column behaves like the terminal area — the same tab bar and its buttons, splitting a
/// pane, opening a browser beside a file — rather than reimplementing those on a bespoke
/// container. The header adds only what a workspace has no notion of: hiding the column.
struct CodeReviewPanelView: View {
    @ObservedObject var state: CodeReviewPanelState
    let windowAppearance: WindowAppearanceSnapshot
    let isFullScreen: Bool
    let isVisibleInUI: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
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

    /// The column's hide button.
    ///
    /// It lives on the column itself so closing it never depends on finding the right menu
    /// or remembering a shortcut. Re-opening is the `</>` button on the terminal tab bar.
    private var header: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            Button {
                state.isVisible = false
            } label: {
                Image(systemName: "sidebar.right")
                    .font(.system(size: 11, weight: .medium))
                    .frame(width: 24, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.trailing, 6)
            .help(String(localized: "codeReview.hideColumn", defaultValue: "Hide Code Review"))
            .accessibilityLabel(String(localized: "codeReview.hideColumn", defaultValue: "Hide Code Review"))
        }
        .frame(height: 22)
    }

    /// Matches what the terminal area gives its selected workspace.
    ///
    /// Not a higher number: portals are window-level AppKit layers, so raising this above the
    /// rest puts the column's surfaces over the whole window — including this view's own hide
    /// button and the column's resize handle, which then cannot be clicked at all.
    private static let portalPriority = 2
}
