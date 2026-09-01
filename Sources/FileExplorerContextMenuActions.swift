import AppKit
import Foundation

/// Context-menu handlers for the file tree.
///
/// Split from `FileExplorerPanelView` so the view file keeps to presenting the outline view.
/// Each
/// method is an `@objc` target for one `NSMenuItem`, and every one of them takes its node
/// from `representedObject` rather than the selection, so acting on a right-clicked row
/// never depends on the click having moved the selection first.
extension FileExplorerPanelView.Coordinator {
    /// The window the tree is in, used to anchor sheets.
    private var hostWindow: NSWindow? { outlineView?.window }

    /// Directory a new item should go into for `node`: the folder itself, or its parent.
    private func containerDirectory(for node: FileExplorerNode) -> URL {
        let url = URL(fileURLWithPath: node.path)
        return node.isDirectory ? url : url.deletingLastPathComponent()
    }

    private func node(from sender: NSMenuItem) -> FileExplorerNode? {
        sender.representedObject as? FileExplorerNode
    }

    // MARK: - Opening

    @objc func contextMenuOpenInCodeReview(_ sender: NSMenuItem) {
        guard let node = node(from: sender), !node.isDirectory else { return }
        if AppDelegate.shared?.showFileInCodeReviewColumn(filePath: node.path) != true {
            onOpenFilePreview(node.path)
        }
    }

    @objc func contextMenuOpenTerminalHere(_ sender: NSMenuItem) {
        guard let node = node(from: sender) else { return }
        guard let workspace = AppDelegate.shared?.tabManager?.selectedWorkspace,
              let pane = workspace.bonsplitController.focusedPaneId
                ?? workspace.bonsplitController.allPaneIds.first else { return }
        _ = workspace.newTerminalSurface(
            inPane: pane,
            focus: true,
            workingDirectory: containerDirectory(for: node).path
        )
    }

    // MARK: - Copying

    @objc func contextMenuCopyFileName(_ sender: NSMenuItem) {
        guard let node = node(from: sender) else { return }
        GhosttyApp.terminalPasteboard.writeString(node.name, to: .general)
    }

    // MARK: - Creating

    @objc func contextMenuNewFile(_ sender: NSMenuItem) {
        guard let node = node(from: sender) else { return }
        guard let name = FileExplorerNamePrompt.run(
            title: String(localized: "fileExplorer.prompt.newFile", defaultValue: "New File"),
            initialValue: "",
            window: hostWindow
        ) else { return }
        perform { _ = try FileExplorerFileOperation.createFile(named: name, in: containerDirectory(for: node)) }
    }

    @objc func contextMenuNewFolder(_ sender: NSMenuItem) {
        guard let node = node(from: sender) else { return }
        guard let name = FileExplorerNamePrompt.run(
            title: String(localized: "fileExplorer.prompt.newFolder", defaultValue: "New Folder"),
            initialValue: "",
            window: hostWindow
        ) else { return }
        perform { _ = try FileExplorerFileOperation.createDirectory(named: name, in: containerDirectory(for: node)) }
    }

    // MARK: - Modifying

    @objc func contextMenuRename(_ sender: NSMenuItem) {
        guard let node = node(from: sender) else { return }
        // Same path as `Return` in the outline: find the selected row's cell and put it
        // into inline rename. The context-menu invocation reselects the target row first
        // so the visible cell is the one we edit — a right-click on an unrelated row
        // otherwise starts editing whichever row was selected before.
        guard let outline = outlineView else {
            // No outline view attached (right-clicks from search results / other surfaces
            // land here with a nil outline). Fall back to the modal prompt so the entry
            // point is not left broken.
            promptRename(for: node)
            return
        }
        let targetRow = outline.row(forItem: node)
        guard targetRow >= 0 else {
            promptRename(for: node)
            return
        }
        outline.selectRowIndexes(IndexSet(integer: targetRow), byExtendingSelection: false)
        renameSelectedNode(in: outline)
    }

    /// Runs the modal rename prompt for one node.
    ///
    /// Kept as the fallback for entry points that do not have a live outline view row
    /// to edit inline (search results, error recovery).
    func promptRename(for node: FileExplorerNode) {
        guard let name = FileExplorerNamePrompt.run(
            title: String(localized: "fileExplorer.prompt.rename", defaultValue: "Rename"),
            initialValue: node.name,
            window: hostWindow
        ), name != node.name else { return }
        perform { _ = try FileExplorerFileOperation.rename(URL(fileURLWithPath: node.path), to: name) }
    }

    @objc func contextMenuDuplicate(_ sender: NSMenuItem) {
        guard let node = node(from: sender) else { return }
        perform { _ = try FileExplorerFileOperation.duplicate(URL(fileURLWithPath: node.path)) }
    }

    @objc func contextMenuMoveToTrash(_ sender: NSMenuItem) {
        guard let node = node(from: sender) else { return }

        // Confirmed even though the Trash is recoverable: the menu item sits next to
        // Duplicate, and a mis-click on a directory would move the whole subtree.
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(
            localized: "fileExplorer.confirm.moveToTrash",
            defaultValue: "Move “\(node.name)” to the Trash?"
        )
        alert.addButton(withTitle: String(localized: "fileExplorer.contextMenu.moveToTrash", defaultValue: "Move to Trash"))
        alert.addButton(withTitle: String(localized: "common.cancel", defaultValue: "Cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        perform { try FileExplorerFileOperation.moveToTrash(URL(fileURLWithPath: node.path)) }
    }

    /// Runs a write and refreshes the tree, reporting failure in a sheet.
    ///
    /// The tree is reloaded rather than patched in place: the provider owns the node graph,
    /// and a hand-patched insert would disagree with it the moment anything else changed
    /// the directory.
    /// Internal so the keyboard-shortcut extension in `FileExplorerKeyboardShortcuts.swift`
    /// can share the same failure path — one behavior, one dialog, one reload.
    func perform(_ work: () throws -> Void) {
        do {
            try work()
            store.reload()
        } catch {
            FileExplorerNamePrompt.presentFailure(error, window: hostWindow)
        }
    }
}

extension NSMenu {
    /// Adds one node-targeted item, the shape every tree menu entry shares.
    ///
    /// - Parameters:
    ///   - title: Menu item title.
    ///   - action: Selector on `target`.
    ///   - target: Object receiving the action.
    ///   - node: Node the action applies to, carried in `representedObject`.
    func addFileExplorerItem(
        title: String,
        action: Selector,
        target: AnyObject,
        node: FileExplorerNode
    ) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = target
        item.representedObject = node
        addItem(item)
    }
}
