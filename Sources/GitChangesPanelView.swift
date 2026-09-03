import AppKit
import SwiftUI

/// The right sidebar's Git tab: the working tree's changed files, split into "Staged
/// Changes" and "Changes" sections — same shape as VS Code's Source Control panel.
///
/// Reads ``FileExplorerStore/gitEntryStatusByPath`` rather than running git itself. That
/// store already refreshes on every directory-watch event and picks between the local and
/// SSH providers, so a list that subscribes to it stays current on both without a timer
/// or a second code path of its own.
///
/// A file that is `MM` in git status (staged and further edited) appears in **both**
/// sections. That is the whole reason for keeping the two sides split in
/// ``GitEntryStatus``: opening the diff from the Staged row runs `git diff --cached`,
/// opening it from the Changes row runs `git diff`, so the user sees exactly the slice
/// each row promises.
struct GitChangesPanelView: View {
    @ObservedObject var store: FileExplorerStore

    /// Folder ids collapsed inside the Staged Changes section. Owned above the `ForEach`
    /// so no row below that boundary holds observable state of its own (upstream #2586).
    /// Kept separate from ``unstagedCollapsedFolders`` so the two sections can be folded
    /// independently — a folder full of staged changes and a folder full of unstaged
    /// changes are different reading tasks.
    @State private var stagedCollapsedFolders: Set<String> = []
    @State private var unstagedCollapsedFolders: Set<String> = []

    var body: some View {
        // Directory markers exist for the file-explorer outline's folder colouring; the
        // Git tab builds its own folder tree from file paths, so they are noise here.
        let entries = store.gitEntryStatusByPath.filter { !$0.value.isDirectoryMarker }
        let stagedByPath: [String: GitFileStatus] = entries.compactMapValues(\.staged)
        let unstagedByPath: [String: GitFileStatus] = entries.compactMapValues(\.unstaged)
        let stagedRows = GitChangeEntry.entries(from: stagedByPath)
        let unstagedRows = GitChangeEntry.entries(from: unstagedByPath)
        let root = store.rootPath
        let style = FileExplorerStyle.current
        // Row diffs run local git against `root`. On an SSH root that path is remote, so
        // local git would either fail or, worse, inspect an unrelated same-named local
        // directory. Rows still render; opening a diff over SSH is not supported yet.
        let canOpenDiff = store.provider is LocalFileExplorerProvider
        // Built above the `ForEach` from the State projections, so the closures handed to
        // rows capture a `Binding`, never `self` (which would drag `store` below the list
        // boundary, upstream #2586).
        let toggleStagedFolder = Self.folderToggler(for: $stagedCollapsedFolders)
        let toggleUnstagedFolder = Self.folderToggler(for: $unstagedCollapsedFolders)

        VStack(spacing: 0) {
            // Count files, not rows: a file with both staged and unstaged edits (`MM`)
            // appears in both sections but is one changed file, matching `git status`.
            header(changeCount: entries.count)

            if stagedRows.isEmpty && unstagedRows.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        if !stagedRows.isEmpty {
                            section(
                                title: String(
                                    localized: "git.staged.section",
                                    defaultValue: "Staged Changes"
                                ),
                                count: stagedByPath.count,
                                rows: GitChangeTreeRow.rows(
                                    entries: stagedRows,
                                    root: root,
                                    collapsedFolders: stagedCollapsedFolders
                                ),
                                style: style,
                                side: .staged,
                                root: root,
                                canOpenDiff: canOpenDiff,
                                onToggleFolder: toggleStagedFolder
                            )
                        }
                        if !unstagedRows.isEmpty {
                            section(
                                title: String(
                                    localized: "git.unstaged.section",
                                    defaultValue: "Changes"
                                ),
                                count: unstagedByPath.count,
                                rows: GitChangeTreeRow.rows(
                                    entries: unstagedRows,
                                    root: root,
                                    collapsedFolders: unstagedCollapsedFolders
                                ),
                                style: style,
                                side: .unstaged,
                                root: root,
                                canOpenDiff: canOpenDiff,
                                onToggleFolder: toggleUnstagedFolder
                            )
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// A folder-toggle closure over one section's collapsed set.
    ///
    /// Static on purpose: the returned closure holds the `Binding` and nothing else, so
    /// handing it to a row below the `ForEach` boundary carries no observable reference.
    private static func folderToggler(for collapsed: Binding<Set<String>>) -> (String) -> Void {
        { path in
            if collapsed.wrappedValue.contains(path) {
                collapsed.wrappedValue.remove(path)
            } else {
                collapsed.wrappedValue.insert(path)
            }
        }
    }

    /// One section: its header, then its rows.
    ///
    /// - Parameter count: Files in the section. Passed in rather than derived from
    ///   `rows`, which only lists what is visible — folding a folder must not make the
    ///   header claim fewer changes.
    @ViewBuilder
    private func section(
        title: String,
        count: Int,
        rows: [GitChangeTreeRow],
        style: FileExplorerStyle,
        side: GitStatusSide,
        root: String,
        canOpenDiff: Bool,
        onToggleFolder: @escaping (String) -> Void
    ) -> some View {
        GitChangesSectionHeader(title: title, count: count)

        ForEach(rows) { row in
            switch row.kind {
            case let .folder(isCollapsed, changeCount):
                GitChangeFolderRow(
                    name: row.name,
                    depth: row.depth,
                    isCollapsed: isCollapsed,
                    changeCount: changeCount,
                    onToggle: { onToggleFolder(row.id) }
                )
            case let .file(entry):
                GitChangeRow(
                    fileName: row.name,
                    depth: row.depth,
                    badge: entry.badge,
                    badgeColor: Color(nsColor: style.gitColor(for: entry.status)),
                    // Captures values only (entry, root, side, canOpenDiff) and calls a
                    // static function: rows live under `ForEach`, and an observable
                    // reference there is what reintroduces the spin loop this codebase
                    // already fixed (upstream #2586). Side is captured by value so the
                    // diff picks the right git command.
                    onOpen: {
                        guard canOpenDiff else { return }
                        Self.openDiff(for: entry, root: root, side: side)
                    }
                )
            }
        }
    }

    /// Which side (staged/unstaged) a section's rows come from.
    private enum GitStatusSide {
        case staged
        case unstaged
    }

    /// Opens one file's diff in the code-review column.
    ///
    /// The side matters for what git command runs:
    /// - `.staged` → `git diff --cached -- <path>`
    /// - `.unstaged` untracked → `git diff --no-index /dev/null <path>`
    /// - `.unstaged` other → `git diff -- <path>`
    private static func openDiff(for entry: GitChangeEntry, root: String, side: GitStatusSide) {
        let commandSide: GitFilePatchCommand.Side
        switch side {
        case .staged:
            commandSide = .staged
        case .unstaged:
            commandSide = entry.status == .untracked ? .untracked : .unstaged
        }
        _ = AppDelegate.shared?.openFileDiffInCodeReviewColumn(
            filePath: entry.path,
            side: commandSide,
            repositoryRoot: root
        )
    }

    /// Change count plus the control that opens the diff.
    ///
    /// The button carries no store reference of its own — it calls through `AppDelegate`,
    /// which is where the CLI pipeline that renders diffs already lives.
    private func header(changeCount: Int) -> some View {
        HStack(spacing: 6) {
            Text(String(
                localized: "git.changes.count",
                defaultValue: "\(changeCount) changed"
            ))
            .font(.system(size: 11))
            .foregroundStyle(.secondary)

            Spacer(minLength: 0)

            Button {
                _ = AppDelegate.shared?.openDiffInCodeReviewColumn(
                    useLastTurnSource: false,
                    for: AppDelegate.shared?.tabManager
                )
            } label: {
                Image(systemName: "chevron.left.forwardslash.chevron.right")
                    .font(.system(size: 11, weight: .medium))
                    .frame(width: 22, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(changeCount == 0)
            .help(String(
                localized: "git.changes.openDiff",
                defaultValue: "Open diff in Code Review"
            ))
            .accessibilityLabel(String(
                localized: "git.changes.openDiff",
                defaultValue: "Open diff in Code Review"
            ))
        }
        .padding(.horizontal, 10)
        .frame(height: 26)
    }

    private var emptyState: some View {
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

/// Section header for the Staged / Changes list. Kept as a small view rather than a
/// bare Text so future affordances (a "stage all" button, a hint badge) attach without
/// touching the outer list layout.
private struct GitChangesSectionHeader: View {
    let title: String
    let count: Int

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            Text("\(count)")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.tertiary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .frame(height: 20)
    }
}

/// Leading inset shared by both row kinds, so badges and disclosure arrows line up per level.
private enum GitChangeRowMetrics {
    static let basePadding: CGFloat = 10
    static let indentPerLevel: CGFloat = 12

    static func leadingPadding(depth: Int) -> CGFloat {
        basePadding + CGFloat(depth) * indentPerLevel
    }
}

/// A directory in the Git tree.
private struct GitChangeFolderRow: View {
    let name: String
    let depth: Int
    let isCollapsed: Bool
    let changeCount: Int
    let onToggle: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 12, alignment: .center)

            Text(name)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
                .truncationMode(.head)

            Text("\(changeCount)")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)
        }
        .padding(.leading, GitChangeRowMetrics.leadingPadding(depth: depth))
        .padding(.trailing, 10)
        .frame(height: 22)
        .background(isHovered ? Color.primary.opacity(0.08) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture(perform: onToggle)
        .onHover { isHovered = $0 }
        .help(isCollapsed
            ? String(localized: "git.changes.expandFolder", defaultValue: "Expand folder")
            : String(localized: "git.changes.collapseFolder", defaultValue: "Collapse folder"))
        .accessibilityLabel(name)
    }
}

/// One changed file in the Git tree.
///
/// Takes plain values only. A row under a `ForEach` that reaches for the store — even to
/// read one property — is what reintroduces the 100% CPU spin loop from upstream #2586.
private struct GitChangeRow: View {
    let fileName: String
    let depth: Int
    let badge: String
    let badgeColor: Color
    let onOpen: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 6) {
            Text(badge)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(badgeColor)
                .frame(width: 12, alignment: .center)

            Text(fileName)
                .font(.system(size: 12))
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 0)
        }
        .padding(.leading, GitChangeRowMetrics.leadingPadding(depth: depth))
        .padding(.trailing, 10)
        .frame(height: 22)
        .background(isHovered ? Color.primary.opacity(0.08) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
        .onHover { isHovered = $0 }
        .help(String(
            localized: "git.changes.openFileDiff",
            defaultValue: "Open this file's diff"
        ))
    }
}
