import AppKit
import SwiftUI

/// The right sidebar's History tab: the working tree's commit history as a list.
///
/// Reads paginated pages from a per-instance ``GitHistoryStore`` and draws each commit as a
/// row of short SHA + subject + author + relative date. The list is a plain `LazyVStack`
/// with one `ForEach` at its root — the same shape as the Git tab, and for the same
/// reason: no view below the boundary holds an observable store reference, so upstream
/// #2586 stays fixed.
///
/// A separate store per view instance is deliberate. It couples the sidebar's paging
/// state to the sidebar's lifetime, so switching a workspace's root does not need any
/// cross-workspace state to reset — the previous instance just disappears.
struct GitHistoryPanelView: View {
    @ObservedObject var store: FileExplorerStore

    @StateObject private var history = GitHistoryStore()

    var body: some View {
        let repositoryRoot = store.rootPath.trimmingCharacters(in: .whitespacesAndNewlines)
        VStack(spacing: 0) {
            header(count: history.commits.count)
            content(repositoryRoot: repositoryRoot)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // `body` reads `store.rootPath`; observing it here keeps the `onChange` on a value
        // SwiftUI already knows how to diff. Empty strings collapse to `nil` inside the
        // store, so the empty case does not thrash.
        .onChange(of: store.rootPath) { _, newRoot in
            history.setRepositoryRoot(newRoot)
            history.loadNextPageIfNeeded(visibleIndex: 0)
        }
        // `FileExplorerStore` already watches the working tree for us; a change in the
        // git-status map is the same signal we would get from watching `.git/HEAD` and
        // its refs, without a second watcher. `refreshIfHeadChanged` short-circuits when
        // the HEAD signature has not actually moved, so file saves that touch untracked
        // files do not cost a `git log`.
        .onChange(of: store.gitStatusByPath) { _, _ in
            history.refreshIfHeadChanged()
        }
        .onAppear {
            history.setRepositoryRoot(store.rootPath)
            history.loadNextPageIfNeeded(visibleIndex: 0)
        }
    }

    @ViewBuilder
    private func content(repositoryRoot: String) -> some View {
        if history.commits.isEmpty {
            emptyState
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(history.commits.enumerated()), id: \.element.id) { index, commit in
                        GitHistoryRow(
                            commit: commit,
                            // A closure, not the store: rows live under `ForEach` and holding
                            // an observable reference there is what reintroduces upstream
                            // #2586. `repositoryRoot` is captured by value.
                            onOpen: {
                                guard !repositoryRoot.isEmpty else { return }
                                _ = AppDelegate.shared?.openCommitDiffInCodeReviewColumn(
                                    sha: commit.sha,
                                    title: "\(commit.shortSHA)  \(commit.subject)",
                                    repositoryRoot: repositoryRoot
                                )
                            }
                        )
                        .onAppear {
                            // The row is now on screen; ask the store to preload the
                            // next page if this is close to the tail.
                            history.loadNextPageIfNeeded(visibleIndex: index)
                        }
                    }
                    if history.isLoading {
                        loadingIndicator
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private func header(count: Int) -> some View {
        HStack(spacing: 6) {
            Text(String(
                localized: "git.history.count",
                defaultValue: "\(count) commits"
            ))
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .frame(height: 26)
    }

    private var emptyState: some View {
        VStack {
            Spacer()
            Text(String(localized: "git.history.empty", defaultValue: "No history"))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var loadingIndicator: some View {
        HStack {
            Spacer()
            ProgressView().controlSize(.small)
            Spacer()
        }
        .padding(.vertical, 6)
    }
}

/// One commit row.
///
/// Takes plain values only. A row under a `ForEach` that reaches for the store would put an
/// observable reference below the list boundary, which is what reintroduces the spin loop
/// this codebase already fixed once (upstream #2586).
private struct GitHistoryRow: View {
    let commit: GitCommitLine
    let onOpen: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(commit.shortSHA)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)

            Text(commit.subject)
                .font(.system(size: 12))
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 8)

            Text(commit.authorName)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)

            Text(GitCommitRelativeDate.string(from: commit.authoredAt))
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .frame(height: 22)
        .background(isHovered ? Color.primary.opacity(0.08) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
        .onHover { isHovered = $0 }
        .help(String(
            localized: "git.history.openCommitDiff",
            defaultValue: "Open this commit's diff"
        ))
    }
}
