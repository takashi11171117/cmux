import AppKit
import SwiftUI

/// The right sidebar's Git tab: the working tree's changed files, as a foldable tree.
///
/// Reads ``FileExplorerStore/gitStatusByPath`` rather than running git itself. That store
/// already refreshes on every directory-watch event and picks between the local and SSH
/// providers, so a list that subscribes to it stays current on both without a timer or a
/// second code path of its own.
struct GitChangesPanelView: View {
    @ObservedObject var store: FileExplorerStore

    /// Folder ids the user has folded shut. Owned here, above the `ForEach`, so no row below
    /// that boundary holds observable state of its own (upstream #2586).
    @State private var collapsedFolders: Set<String> = []

    var body: some View {
        let entries = GitChangeEntry.entries(from: store.gitStatusByPath)
        let root = store.rootPath
        let rows = GitChangeTreeRow.rows(
            entries: entries,
            root: root,
            collapsedFolders: collapsedFolders
        )
        // Same entry point the outline view uses for its change marks
        // `[Sources/FileExplorerView.swift:122]`, so a file's colour is identical in both
        // places. A second palette here would make one file look like two different things.
        let style = FileExplorerStyle.current
        // Built once, above the `ForEach`: rows get closures, never the store.
        let actions = GitChangeTreeActions(
            openDiff: { entry in openDiff(for: entry, root: root) },
            toggleFolder: { path in
                if collapsedFolders.contains(path) {
                    collapsedFolders.remove(path)
                } else {
                    collapsedFolders.insert(path)
                }
            }
        )

        VStack(spacing: 0) {
            header(changeCount: entries.count)

            if entries.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(rows) { row in
                            switch row.kind {
                            case let .folder(isCollapsed, changeCount):
                                GitChangeFolderRow(
                                    name: row.name,
                                    depth: row.depth,
                                    isCollapsed: isCollapsed,
                                    changeCount: changeCount,
                                    onToggle: { actions.toggleFolder(row.id) }
                                )
                            case let .file(entry):
                                GitChangeRow(
                                    fileName: row.name,
                                    depth: row.depth,
                                    badge: entry.badge,
                                    badgeColor: Color(nsColor: style.gitColor(for: entry.status)),
                                    onOpen: { actions.openDiff(entry) }
                                )
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Opens one file's diff in the code-review column.
    ///
    /// - Parameters:
    ///   - entry: The clicked row.
    ///   - root: Directory the list is rooted at, used as the git working directory.
    private func openDiff(for entry: GitChangeEntry, root: String) {
        _ = AppDelegate.shared?.openFileDiffInCodeReviewColumn(
            filePath: entry.path,
            isUntracked: entry.status == .untracked,
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

/// What a row can ask the panel to do.
///
/// A struct of closures built above the `ForEach`, following the same pattern as
/// `IndexSectionActions` in `Sources/SessionIndexView.swift`: rows need behaviour, and this is
/// how they get it without a reference to anything observable.
private struct GitChangeTreeActions {
    let openDiff: (GitChangeEntry) -> Void
    let toggleFolder: (String) -> Void
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
/// Takes plain values only. A row under a `ForEach` that reaches for the store — even to read
/// one property — is what reintroduces the 100% CPU spin loop from upstream #2586.
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
