import AppKit
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
        let entries = GitChangeEntry.entries(from: store.gitStatusByPath)
        let root = store.rootPath
        // Same entry point the outline view uses for its change marks
        // `[Sources/FileExplorerView.swift:122]`, so a file's colour is identical in both
        // places. A second palette here would make one file look like two different things.
        let style = FileExplorerStyle.current

        VStack(spacing: 0) {
            header(changeCount: entries.count)

            if entries.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(entries) { entry in
                            GitChangeRow(
                                fileName: entry.fileName,
                                directory: entry.relativeDirectory(from: root),
                                badge: entry.badge,
                                badgeColor: Color(nsColor: style.gitColor(for: entry.status)),
                                // A closure, not the store: rows live under a `ForEach`, and
                                // holding an observable reference there is what brings back
                                // the spin loop (upstream #2586).
                                onOpen: { openDiff(for: entry, root: root) }
                            )
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

/// One row of the Git list.
///
/// Takes plain values only. A row under a `ForEach` that reaches for the store — even to read
/// one property — is what reintroduces the 100% CPU spin loop from upstream #2586.
private struct GitChangeRow: View {
    let fileName: String
    let directory: String?
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

            if let directory {
                Text(directory)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
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
