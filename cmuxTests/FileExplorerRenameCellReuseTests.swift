import AppKit
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

/// Inline rename on a recycled file-explorer cell.
///
/// The bug: `NSOutlineView` recycles `FileExplorerCellView`, and the cell kept the rename
/// callbacks of the row it used to display. After a refresh the same cell could commit a
/// typed name against the previous row's file — so the panel showed the new name while a
/// different file (or none) had actually been renamed.
@MainActor
@Suite("File explorer rename cell reuse")
struct FileExplorerRenameCellReuseTests {
    @Test("Reconfiguring a cell disarms the rename left by the previous row")
    func configureClearsStaleRenameCallbacks() {
        let cell = FileExplorerCellView(identifier: NSUserInterfaceItemIdentifier("FileExplorerCell"))
        cell.configure(with: FileExplorerNode(name: "old.txt", path: "/tmp/old.txt", isDirectory: false))

        var committed: [String] = []
        var cancelled = 0
        cell.onRenameCommit = { committed.append($0) }
        cell.onRenameCancel = { cancelled += 1 }

        // The outline view hands this cell to another row.
        cell.configure(with: FileExplorerNode(name: "other.txt", path: "/tmp/other.txt", isDirectory: false))

        #expect(cell.onRenameCommit == nil)
        #expect(cell.onRenameCancel == nil)
        #expect(!cell.isRenamingActive)
        #expect(committed.isEmpty, "recycling is not a commit")
        #expect(cancelled == 0, "recycling is not a cancel either — the row simply changed")
    }

    @Test("A recycled cell shows the new row's name, not the text left in the field")
    func configureRestoresTheLabelAfterAnAbandonedEdit() {
        let cell = FileExplorerCellView(identifier: NSUserInterfaceItemIdentifier("FileExplorerCell"))
        cell.configure(with: FileExplorerNode(name: "old.txt", path: "/tmp/old.txt", isDirectory: false))
        cell.onRenameCommit = { _ in }

        cell.configure(with: FileExplorerNode(name: "other.txt", path: "/tmp/other.txt", isDirectory: false))

        #expect(cell.displayedNameForTesting == "other.txt")
    }
}
