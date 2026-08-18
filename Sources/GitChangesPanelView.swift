import SwiftUI

/// The right sidebar's Git tab: the working tree's changed files, as a list.
///
/// Reads ``FileExplorerStore/gitStatusByPath`` rather than running git itself. That store
/// already refreshes on every directory-watch event and picks between the local and SSH
/// providers, so a list that subscribes to it stays current on both without a timer or a
/// second code path of its own.
struct GitChangesPanelView: View {
    @ObservedObject var store: FileExplorerStore

    var body: some View {
        // Placeholder: the list itself is GIT 02. This exists so the tab is reachable and
        // the mode is wired end to end before any of its content is written.
        VStack {
            Spacer()
            Text(String(localized: "git.changes.empty", defaultValue: "No changes"))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
