import AppKit
import CmuxSettings
import CmuxWorkspaces

/// Perform the configured action for opening a local file from the file explorer.
///
/// - Parameters:
///   - path: Absolute path of the file to open.
///   - workspaceRoot: Directory the explorer is rooted at, so an editor that opens folders as
///     projects is handed the project rather than the bare file.
///   - onOpenFilePreview: Opens the file in cmux's own preview instead.
@MainActor
func performFileExplorerFileOpen(
    path: String,
    workspaceRoot: String?,
    onOpenFilePreview: (String) -> Void
) {
    let action = FileExplorerDoubleClickActionSettings.resolvedAction()
    let hasPreferredEditor = PreferredEditorSettingsStore(defaults: .standard).resolvedCommand != nil
    switch FileExplorerDoubleClickActionSettings.fileActivation(
        action: action,
        hasPreferredEditorCommand: hasPreferredEditor
    ) {
    case .preview:
        onOpenFilePreview(path)
    case .defaultEditor:
        FileExternalOpenAction.openDefault(fileURL: URL(fileURLWithPath: path), workspaceRoot: workspaceRoot)
    case .preferredEditor:
        PreferredEditorService(defaults: .standard).open(URL(fileURLWithPath: path))
    }
}

@MainActor
extension FileExplorerPanelView.Coordinator {
    func openSelectedNode(in outlineView: NSOutlineView) {
        guard let row = resolvedSelectionRow(in: outlineView) else { return }
        openNode(in: outlineView, at: row)
    }

    /// Puts the selected row into VS Code-style inline rename.
    ///
    /// Not a modal dialog: the cell's name label flips to an editable field, focus lands
    /// there, and the base name (everything before the extension) is selected so a retype
    /// only overwrites the base. Applied on `Return`, cancelled on `Esc`, committed on
    /// focus loss — all handled by ``FileExplorerCellView.beginRename()``.
    func renameSelectedNode(in outlineView: NSOutlineView) {
        guard let row = resolvedSelectionRow(in: outlineView),
              row >= 0,
              let node = outlineView.item(atRow: row) as? FileExplorerNode,
              let cell = outlineView.view(atColumn: 0, row: row, makeIfNecessary: false)
                as? FileExplorerCellView
        else { return }
        cell.onRenameCommit = { [weak self] newName in
            guard let self else { return }
            self.perform {
                _ = try FileExplorerFileOperation.rename(
                    URL(fileURLWithPath: node.path),
                    to: newName
                )
            }
        }
        cell.onRenameCancel = { }
        cell.beginRename()
    }

    func openNode(in outlineView: NSOutlineView, at row: Int) {
        guard row >= 0,
              let node = outlineView.item(atRow: row) as? FileExplorerNode else { return }

        if node.isDirectory {
            if outlineView.isItemExpanded(node) {
                outlineView.collapseItem(node)
            } else if outlineView.isExpandable(node) {
                outlineView.expandItem(node)
            }
            return
        }

        guard store.provider is LocalFileExplorerProvider else {
            onOpenFilePreview(node.path)
            return
        }
        performFileExplorerFileOpen(
            path: node.path,
            workspaceRoot: store.rootPath,
            onOpenFilePreview: onOpenFilePreview
        )
    }
}

extension FileExplorerNSOutlineView {
    func handleOpenSelectionShortcut(_ event: NSEvent) -> Bool {
        guard event.isFileExplorerOpenSelectionShortcut(in: fileExplorerPanelPlacement) else { return false }
        endQuickSearch()
        fileExplorerCoordinator?.openSelectedNode(in: self)
        return true
    }
}

extension FileExplorerSearchResultsTableView {
    func handleOpenSelectionShortcut(_ event: NSEvent) -> Bool {
        guard event.isFileExplorerOpenSelectionShortcut(in: fileExplorerPanelPlacement) else { return false }
        onCommit?()
        return true
    }
}

extension FileExplorerSearchField {
    func handleOpenSelectionShortcut(_ event: NSEvent) -> Bool {
        if (currentEditor() as? NSTextView)?.hasMarkedText() == true { return false }
        guard !RightSidebarKeyboardNavigation.isPlainPrintableText(event) else { return false }
        guard event.isFileExplorerOpenSelectionShortcut(in: fileExplorerPanelPlacement) else { return false }
        onCommit?()
        return true
    }
}

@MainActor
extension NSEvent {
    func isFileExplorerOpenSelectionShortcut(in placement: FileExplorerPanelPlacement) -> Bool {
        isFileExplorerOpenSelectionShortcut(in: placement.openSelectionShortcutContext(for: self))
    }

    func isFileExplorerOpenSelectionShortcut(in context: ShortcutContext) -> Bool {
        KeyboardShortcutSettings.Action.fileExplorerOpenSelectionActions.contains { action in
            KeyboardShortcutSettings.shortcut(for: action).matches(event: self) &&
                KeyboardShortcutSettings.effectiveWhenClause(for: action).evaluate(context)
        }
    }
}

@MainActor
private extension FileExplorerPanelPlacement {
    func openSelectionShortcutContext(for event: NSEvent) -> ShortcutContext {
        var context = AppDelegate.shared?.shortcutEventFocusContext(event).shortcutContext ??
            ShortcutFocusState(browser: false, markdown: false, sidebar: false).context
        switch self {
        case .rightSidebar, .pane:
            context.setBool(ShortcutFocusAtom.sidebarFocus.rawValue, true)
            context.setBool(ShortcutFocusAtom.browserFocus.rawValue, false)
            context.setBool(ShortcutFocusAtom.markdownFocus.rawValue, false)
            context.setBool(ShortcutFocusAtom.terminalFocus.rawValue, false)
        }
        return context
    }
}

private extension KeyboardShortcutSettings.Action {
    static var fileExplorerOpenSelectionActions: [Self] {
        [.fileExplorerOpenSelection, .fileExplorerOpenSelectionFinderAlias]
    }

    static var fileExplorerRenameSelectionActions: [Self] {
        [.fileExplorerRenameSelection]
    }
}

@MainActor
extension NSEvent {
    func isFileExplorerRenameSelectionShortcut(in placement: FileExplorerPanelPlacement) -> Bool {
        isFileExplorerRenameSelectionShortcut(in: placement.openSelectionShortcutContext(for: self))
    }

    func isFileExplorerRenameSelectionShortcut(in context: ShortcutContext) -> Bool {
        KeyboardShortcutSettings.Action.fileExplorerRenameSelectionActions.contains { action in
            KeyboardShortcutSettings.shortcut(for: action).matches(event: self) &&
                KeyboardShortcutSettings.effectiveWhenClause(for: action).evaluate(context)
        }
    }
}
