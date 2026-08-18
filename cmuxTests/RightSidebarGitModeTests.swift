import Foundation
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

/// Covers wiring the Git tab into the right sidebar.
///
/// Two of the places a new mode has to be named are not `switch` statements — `from(cliArgument:)`
/// has a `default`, and `paneModes` is an array literal — so the compiler stays silent when they
/// are missed and the mode is merely unreachable from the CLI, or silently non-pane. Those two
/// are the reason this suite exists.
@Suite("RightSidebarMode.git")
struct RightSidebarGitModeTests {
    @Test("the CLI can select it")
    func cliArgumentResolves() {
        #expect(RightSidebarMode.from(cliArgument: "git") == .git)
        #expect(RightSidebarMode.from(cliArgument: "GIT") == .git)
        #expect(RightSidebarMode.from(cliArgument: " git ") == .git)
    }

    @Test("it is offered as a tab")
    func isAvailable() {
        let modes = RightSidebarMode.availableModes(feedEnabled: false, dockEnabled: false)
        #expect(modes.contains(.git))
    }

    @Test("it sits directly after Files in the tab strip")
    func tabOrderFollowsDeclaration() {
        // The strip maps `availableModes()`, which is `allCases.filter` with no reordering,
        // so declaration order is what the user sees.
        let modes = RightSidebarMode.availableModes(feedEnabled: false, dockEnabled: false)
        guard let files = modes.firstIndex(of: .files), let git = modes.firstIndex(of: .git) else {
            Issue.record("files or git missing from available modes")
            return
        }
        #expect(git == files + 1)
    }

    @Test("the file explorer store is kept in sync for it")
    func storeIsSynced() {
        // Without this the store's root is set to `.none` and git status is never fetched,
        // so the list would render empty forever.
        #expect(FileExplorerRootSyncPolicy.shouldSyncFileExplorerStore(
            isRightSidebarVisible: true, mode: .git
        ))
    }

    @Test("it is not synced while the sidebar is hidden")
    func hiddenSidebarSkipsSync() {
        #expect(!FileExplorerRootSyncPolicy.shouldSyncFileExplorerStore(
            isRightSidebarVisible: false, mode: .git
        ))
    }

    @Test("it is not offered as a pane")
    func notAPaneMode() {
        // The list launches diffs into the code-review column; as a pane it would be a narrow
        // list sitting next to the thing it opens.
        #expect(!RightSidebarMode.paneModes.contains(.git))
        #expect(!RightSidebarMode.git.canOpenAsPane)
    }

    @Test("it round-trips through its raw value")
    func codableRawValue() {
        // The mode is persisted by raw value, so a rename would silently reset a user's tab.
        #expect(RightSidebarMode.git.rawValue == "git")
        #expect(RightSidebarMode(rawValue: "git") == .git)
    }

    @Test("it carries a label and a symbol")
    func hasPresentation() {
        #expect(!RightSidebarMode.git.label.isEmpty)
        #expect(!RightSidebarMode.git.symbolName.isEmpty)
    }

    @Test("adding it did not disturb the existing modes")
    func existingModesUnchanged() {
        #expect(RightSidebarMode.from(cliArgument: "files") == .files)
        #expect(RightSidebarMode.from(cliArgument: "find") == .find)
        #expect(RightSidebarMode.from(cliArgument: "vault") == .sessions)
        #expect(RightSidebarMode.from(cliArgument: "sessions") == .sessions)
        #expect(RightSidebarMode.paneModes == [.files, .find, .sessions])
    }
}
