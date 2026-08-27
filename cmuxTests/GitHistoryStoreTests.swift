import Foundation
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

/// How the paged commit list is stitched together.
///
/// The bugs these prevent: (1) a commit that lands twice — because a new commit at the top
/// of the branch pushes the next page's SHAs down by one — rendering twice in the sidebar;
/// (2) reaching the end of history but still asking git for another empty page every
/// scroll; (3) leftover commits from an old repository lingering after the sidebar switches
/// roots.
@MainActor
@Suite("Git history store", .serialized)
struct GitHistoryStoreTests {
    /// Test stub that returns fixed pages by (skip → commits) mapping.
    private final actor Stub: GitHistoryReading {
        private var pages: [Int: [GitCommitLine]]
        private(set) var callCount = 0
        private(set) var callLog: [(skip: Int, maxCount: Int)] = []

        init(pages: [Int: [GitCommitLine]]) {
            self.pages = pages
        }

        func page(repositoryRoot: String, maxCount: Int, skip: Int) async -> [GitCommitLine] {
            callCount += 1
            callLog.append((skip: skip, maxCount: maxCount))
            let page = pages[skip] ?? []
            // Truncate to maxCount so a stub setup for a big page can be reused as a small
            // one without editing every fixture.
            return Array(page.prefix(maxCount))
        }

        func patch(repositoryRoot: String, sha: String) async -> String? { nil }

        func setPage(skip: Int, commits: [GitCommitLine]) { pages[skip] = commits }
    }

    private func commit(_ sha: String, subject: String = "s") -> GitCommitLine {
        // Fill the required fields with anything: none of these tests read them, they only
        // look at SHAs and counts.
        GitCommitLine(
            sha: sha,
            shortSHA: String(sha.prefix(7)),
            parents: [],
            authorName: "T",
            authoredAt: Date(timeIntervalSince1970: 0),
            subject: subject,
            refNames: []
        )
    }

    private func makeStore(
        stub: Stub,
        pageSize: Int = 4,
        prefetchDistance: Int = 1
    ) -> GitHistoryStore {
        GitHistoryStore(service: stub, pageSize: pageSize, prefetchDistance: prefetchDistance)
    }

    private func settle(_ store: GitHistoryStore) async {
        // Await the store's in-flight page task if any. Guessing at a number of
        // Task.yield() calls was flaky: the first apply runs on the main actor after the
        // actor hop, which takes more than one hop to land under Xcode's dispatcher.
        await store.pendingLoad?.value
    }

    @Test("The first row's onAppear triggers the initial page")
    func firstAppearTriggersInitialPage() async {
        let stub = Stub(pages: [0: [commit("a"), commit("b"), commit("c"), commit("d")]])
        let store = makeStore(stub: stub)
        store.setRepositoryRoot("/tmp/r")

        store.loadNextPageIfNeeded(visibleIndex: 0)
        await settle(store)

        #expect(store.commits.map(\.sha) == ["a", "b", "c", "d"])
        #expect(await stub.callCount == 1)
    }

    @Test("A visible row well before the tail does not preload")
    func earlyRowDoesNotPreload() async {
        let page0 = (0..<4).map { commit("p0_\($0)") }
        let stub = Stub(pages: [0: page0])
        let store = makeStore(stub: stub, prefetchDistance: 1)
        store.setRepositoryRoot("/tmp/r")

        store.loadNextPageIfNeeded(visibleIndex: 0)
        await settle(store)
        // At this point commits.count == 4, prefetch distance = 1. Row 0 is far from the
        // tail (row 3). One more call would be a wasteful `git log`.
        store.loadNextPageIfNeeded(visibleIndex: 0)
        await settle(store)

        #expect(await stub.callCount == 1)
    }

    @Test("Approaching the tail asks for the next page")
    func tailApproachAsksNextPage() async {
        let page0 = (0..<4).map { commit("p0_\($0)") }
        let page1 = (0..<4).map { commit("p1_\($0)") }
        let stub = Stub(pages: [0: page0, 4: page1])
        let store = makeStore(stub: stub, prefetchDistance: 1)
        store.setRepositoryRoot("/tmp/r")

        store.loadNextPageIfNeeded(visibleIndex: 0)
        await settle(store)
        // Row 3 is exactly the last row; count - prefetchDistance = 3, so this fires.
        store.loadNextPageIfNeeded(visibleIndex: 3)
        await settle(store)

        #expect(store.commits.count == 8)
        #expect(await stub.callCount == 2)
        // The second call must skip past the first page — otherwise the same 4 commits
        // come back and get deduped, wasting a full `git log`.
        let calls = await stub.callLog
        #expect(calls[1].skip == 4)
    }

    @Test("A commit that comes back in two pages is not shown twice")
    func duplicateAcrossPagesIsDedeuped() async {
        // Simulate what happens if a commit is added between page 0 and page 1: the next
        // page's window shifts by one and the last SHA of page 0 reappears as the first of
        // page 1. Without dedup, the sidebar would render it twice.
        let page0 = [commit("a"), commit("b"), commit("c"), commit("d")]
        let page1 = [commit("d"), commit("e"), commit("f"), commit("g")]
        let stub = Stub(pages: [0: page0, 4: page1])
        let store = makeStore(stub: stub, prefetchDistance: 1)
        store.setRepositoryRoot("/tmp/r")

        store.loadNextPageIfNeeded(visibleIndex: 0)
        await settle(store)
        store.loadNextPageIfNeeded(visibleIndex: 3)
        await settle(store)

        #expect(store.commits.map(\.sha) == ["a", "b", "c", "d", "e", "f", "g"])
    }

    @Test("A page shorter than requested marks the end")
    func shortPageReachesEnd() async {
        // Requested 4, got 2. The rest of history does not exist, and asking git for
        // another empty page would be a wasted trip on every scroll thereafter.
        let stub = Stub(pages: [0: [commit("a"), commit("b")]])
        let store = makeStore(stub: stub, prefetchDistance: 1)
        store.setRepositoryRoot("/tmp/r")

        store.loadNextPageIfNeeded(visibleIndex: 0)
        await settle(store)

        #expect(store.reachedEnd == true)
        #expect(store.commits.count == 2)

        // Even a scroll right up to the tail must not fire another page.
        store.loadNextPageIfNeeded(visibleIndex: 1)
        await settle(store)
        #expect(await stub.callCount == 1)
    }

    @Test("An exact-size page does not falsely mark the end")
    func exactPageDoesNotMarkEnd() async {
        let page0 = (0..<4).map { commit("p0_\($0)") }
        // Page 1 is not stubbed, so it returns []; but that comes later.
        let stub = Stub(pages: [0: page0])
        let store = makeStore(stub: stub, prefetchDistance: 1)
        store.setRepositoryRoot("/tmp/r")

        store.loadNextPageIfNeeded(visibleIndex: 0)
        await settle(store)

        // At this moment reachedEnd should be false, because we don't yet know: a full
        // page came back and there might be more.
        #expect(store.reachedEnd == false)
    }

    @Test("Switching to a different repository drops the old commits")
    func switchingRepositoryClearsCommits() async {
        let stub = Stub(pages: [0: [commit("a"), commit("b"), commit("c"), commit("d")]])
        let store = makeStore(stub: stub, prefetchDistance: 1)

        store.setRepositoryRoot("/tmp/one")
        store.loadNextPageIfNeeded(visibleIndex: 0)
        await settle(store)
        #expect(store.commits.count == 4)

        store.setRepositoryRoot("/tmp/two")
        // Immediately after the switch, before the next load, the old commits must be gone.
        #expect(store.commits.isEmpty)
        #expect(store.reachedEnd == false)
    }

    @Test("Setting the same root twice does not thrash the list")
    func sameRootTwiceIsNoop() async {
        let stub = Stub(pages: [0: [commit("a"), commit("b"), commit("c"), commit("d")]])
        let store = makeStore(stub: stub, prefetchDistance: 1)
        store.setRepositoryRoot("/tmp/r")
        store.loadNextPageIfNeeded(visibleIndex: 0)
        await settle(store)

        // A view re-syncing to the same root should not blank the list.
        store.setRepositoryRoot("/tmp/r")

        #expect(store.commits.count == 4)
    }

    @Test("An empty path is treated as no repository")
    func emptyPathClearsRepository() async {
        let stub = Stub(pages: [0: [commit("a")]])
        let store = makeStore(stub: stub, prefetchDistance: 1)
        store.setRepositoryRoot("/tmp/r")
        store.loadNextPageIfNeeded(visibleIndex: 0)
        await settle(store)

        store.setRepositoryRoot("")
        store.loadNextPageIfNeeded(visibleIndex: 0)
        await settle(store)

        // No load must happen for a nil / empty root.
        #expect(store.commits.isEmpty)
        #expect(await stub.callCount == 1)
    }
}
