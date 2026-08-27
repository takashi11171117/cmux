import Combine
import Foundation

/// Manages the working tree's commit history as the History sidebar sees it.
///
/// The store is what turns a raw stream of pages from ``GitHistoryService`` into a stable
/// list the sidebar can render: it stitches pages together, drops SHAs it has already seen,
/// decides when the list has reached its end, and forgets everything when the repository
/// root changes. All git launches happen on ``GitHistoryService``'s actor; the store never
/// touches `Process` itself, so the main thread never blocks on a `git log`.
///
/// Ownership: one store per sidebar instance, held as an `@StateObject` above the `ForEach`
/// so no row below that boundary holds an observable reference of its own — the same
/// discipline that keeps ``GitChangesPanelView`` clear of upstream #2586. Rows receive
/// values and closures, never the store.
@MainActor
final class GitHistoryStore: ObservableObject {
    /// The list the sidebar renders, in the order git returned it (newest first).
    @Published private(set) var commits: [GitCommitLine] = []

    /// Whether a page is currently in flight. Views can read this to draw a spinner without
    /// racing a fresh load.
    @Published private(set) var isLoading = false

    /// `true` once a page came back short. When this is set, no further paging will run;
    /// see ``endReached`` for the reasoning.
    @Published private(set) var reachedEnd = false

    /// Absolute path of the repository being read, or `nil` when there is no repository (or
    /// the sidebar is not yet mounted). Setting this to a different value drops the entire
    /// list, since the old commits belong to a different repository.
    private(set) var repositoryRoot: String?

    private let service: any GitHistoryReading
    private let pageSize: Int
    private let prefetchDistance: Int

    /// SHAs already in ``commits``, kept in a `Set` so the paging arithmetic can dedupe in
    /// O(1). Page boundaries move when a commit is created between two requests, so the
    /// same commit can arrive twice — and the store must not double-render it.
    private var seenSHAs: Set<String> = []

    /// Generation counter bumped on every `setRepositoryRoot` and every explicit refresh.
    /// A page in flight when the root changes has its result discarded on comparison.
    private var generation = 0

    /// The last HEAD signature we read, used by ``refreshIfHeadChanged()`` to skip work
    /// when the tip has not moved. Nil means "we have not asked yet" and forces a load on
    /// the first call.
    private var lastHeadSignature: String?

    /// In-flight page load, exposed so tests can `await` it instead of guessing at a
    /// number of `Task.yield()`s. Nil when no page is loading.
    ///
    /// Internal rather than private for testing alone; nothing in the app should reach for
    /// this. Same discipline as ``FilePreviewSyntaxHighlightController/debounceTask``.
    private(set) var pendingLoad: Task<Void, Never>?

    /// - Parameters:
    ///   - service: The reader that runs `git log`. Injected so tests can swap in a
    ///     stub — see ``GitHistoryReading``.
    ///   - pageSize: Commits fetched per page. Default 200, provisional — real value gets
    ///     settled in HIST 03 after measuring against a large repo.
    ///   - prefetchDistance: How close to the last row a scroll needs to get before the
    ///     next page starts loading. Measured in rows, not pixels.
    init(
        service: any GitHistoryReading = GitHistoryService(),
        pageSize: Int = 200,
        prefetchDistance: Int = 20
    ) {
        self.service = service
        self.pageSize = pageSize
        self.prefetchDistance = prefetchDistance
    }

    /// Switches the store to a new repository, or clears it when `path` is nil or empty.
    ///
    /// The whole list drops on every call, even when the path is unchanged, only when the
    /// caller explicitly asks — the `path` check here reduces churn for the common case of
    /// the sidebar re-syncing to the same root.
    ///
    /// - Parameter path: The new repository root, or `nil` to clear.
    func setRepositoryRoot(_ path: String?) {
        let normalized = path?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolved = (normalized?.isEmpty ?? true) ? nil : normalized
        guard resolved != repositoryRoot else { return }
        repositoryRoot = resolved
        clear()
        // A view calling `loadNextPageIfNeeded(visibleIndex: 0)` next tick will do the
        // initial load; we do not fire it from here so callers stay in charge of when git
        // gets touched.
    }

    /// Asks the store to make sure a page beyond the visible row exists.
    ///
    /// Called from an `onAppear` on the row — never from `body`. Doing this from `body`
    /// would re-fire on every SwiftUI pass and can, in the wrong shape, put a state write
    /// inside a body evaluation. The `onAppear` seam avoids both.
    ///
    /// - Parameter visibleIndex: The row that just appeared. When this row is within
    ///   `prefetchDistance` of the current end of the list, the next page loads.
    func loadNextPageIfNeeded(visibleIndex: Int) {
        guard let repositoryRoot,
              !isLoading,
              !reachedEnd
        else { return }
        // The very first call has commits.count == 0 and visibleIndex == 0, which is what
        // triggers the initial load. After that the check is "is the last row we've drawn
        // close enough to the end that a scroll would run out?"
        let threshold = max(0, commits.count - prefetchDistance)
        guard visibleIndex >= threshold else { return }
        loadNextPage(repositoryRoot: repositoryRoot)
    }

    /// Re-reads the first page if HEAD has moved (a commit, a checkout, a rebase).
    ///
    /// Calling this while a page is in flight is safe: the current page's generation is
    /// bumped, its result is dropped, and this refresh starts fresh. Cheaper than polling
    /// git for every file save.
    func refreshIfHeadChanged() {
        guard let repositoryRoot else { return }
        let signature = HistoryHeadReader.headSignature(at: repositoryRoot)
        guard signature != lastHeadSignature else { return }
        lastHeadSignature = signature
        // A HEAD change might have added commits, removed commits (rebase) or replaced the
        // history entirely (checkout). Reset the list and re-page from the top.
        clear()
        loadNextPage(repositoryRoot: repositoryRoot)
    }

    private func clear() {
        commits = []
        seenSHAs = []
        reachedEnd = false
        isLoading = false
        generation &+= 1
        // lastHeadSignature is deliberately preserved: after `setRepositoryRoot` we want
        // the first `refreshIfHeadChanged` to still detect a change if the caller last
        // saw a different repository. But when we clear from within `refreshIfHeadChanged`
        // itself, `lastHeadSignature` was updated moments before, so this order is safe.
    }

    private func loadNextPage(repositoryRoot: String) {
        isLoading = true
        let capturedGeneration = generation
        let skip = commits.count
        pendingLoad = Task {
            let page = await service.page(
                repositoryRoot: repositoryRoot,
                maxCount: pageSize,
                skip: skip
            )
            self.applyPageIfCurrent(page, generation: capturedGeneration)
            self.pendingLoad = nil
        }
    }

    private func applyPageIfCurrent(
        _ page: [GitCommitLine],
        generation: Int
    ) {
        guard generation == self.generation else { return }
        isLoading = false
        // The "end" signal is "the page came back shorter than we asked". Waiting for an
        // empty page instead would spend one extra `git log` invocation per repository
        // just to conclude "no more".
        if page.count < pageSize {
            reachedEnd = true
        }
        guard !page.isEmpty else { return }
        var appended: [GitCommitLine] = []
        appended.reserveCapacity(page.count)
        for commit in page where seenSHAs.insert(commit.sha).inserted {
            appended.append(commit)
        }
        commits.append(contentsOf: appended)
    }
}

/// Reads the git HEAD signature synchronously, without booting a whole service actor.
///
/// This is deliberately *not* on ``GitHistoryService``. Reading `HEAD` and one ref file is
/// a two-stat operation; it is cheaper to do it in place than to hop through an actor for
/// the answer. The service is the seam for anything that shells out to `git`, which this
/// does not.
///
/// - Parameter repositoryRoot: A path inside the working tree. The function walks up to
///   find `.git` and reads `HEAD` from there.
/// - Returns: A string uniquely identifying the current HEAD (branch name plus its ref
///   value, or a detached SHA), or `nil` when there is no `.git` above the path.
enum HistoryHeadReader {
    static func headSignature(at repositoryRoot: String) -> String? {
        var current = URL(fileURLWithPath: repositoryRoot).standardizedFileURL
        while true {
            let candidate = current.appendingPathComponent(".git")
            if let contents = try? String(contentsOf: candidate.appendingPathComponent("HEAD"), encoding: .utf8) {
                return signature(from: contents.trimmingCharacters(in: .whitespacesAndNewlines),
                                 gitDirectory: candidate)
            }
            let parent = current.deletingLastPathComponent()
            if parent == current { return nil }
            current = parent
        }
    }

    private static func signature(from headContents: String, gitDirectory: URL) -> String {
        let refPrefix = "ref: "
        guard headContents.hasPrefix(refPrefix) else {
            // Detached HEAD: the file holds the SHA verbatim, which is already a fine
            // signature on its own.
            return headContents
        }
        let refName = String(headContents.dropFirst(refPrefix.count))
        let refURL = gitDirectory.appendingPathComponent(refName)
        let refValue = (try? String(contentsOf: refURL, encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        // Include both the branch name and its value: a checkout that lands on a branch
        // whose SHA happens to match the current one still changes the branch component,
        // which is what tells the sidebar to reload.
        return "\(refName)\u{0}\(refValue)"
    }
}
