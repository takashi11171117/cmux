import SwiftUI

/// The right sidebar's History tab.
///
/// Empty placeholder for HIST 01. The list, the paging and the click-to-diff wiring are
/// added in HIST 03; keeping this file present here lets `RightSidebarPanelView`'s
/// `contentForMode` switch stay exhaustive without an intermediate `EmptyView`, so the
/// day-of-implementation surface is just filling in a body.
struct GitHistoryPanelView: View {
    @ObservedObject var store: FileExplorerStore

    var body: some View {
        VStack {
            Spacer()
            Text(String(
                localized: "git.history.placeholder",
                defaultValue: "History coming soon"
            ))
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
