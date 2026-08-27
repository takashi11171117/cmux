import Foundation
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

/// What the graph renderer puts into the HTML.
///
/// The renderer is a value type on purpose so its output is testable without a WebView.
/// The tests here look for structural properties — the SVG has the expected number of
/// dots, the row markup carries the commit sha as an anchor for click handling — rather
/// than pinning down exact pixel coordinates. Layout numbers are a design surface; a test
/// that hard-codes them makes visual tweaks a chore.
@Suite("Git graph renderer")
struct GitGraphRendererTests {
    private func commit(_ sha: String, parents: [String] = [], subject: String = "s",
                         refs: [String] = []) -> GitCommitLine {
        GitCommitLine(
            sha: sha,
            shortSHA: String(sha.prefix(7)),
            parents: parents,
            authorName: "T",
            authoredAt: Date(timeIntervalSince1970: 0),
            subject: subject,
            refNames: refs
        )
    }

    @Test("Every commit gets one dot in the SVG")
    func onePagePerDot() {
        let commits = [
            commit("c", parents: ["b"]),
            commit("b", parents: ["a"]),
            commit("a"),
        ]
        let nodes = GitGraphLayout.layout(commits)
        let html = GitGraphRenderer.html(commits: commits, nodes: nodes)

        let dotCount = html.components(separatedBy: "<circle").count - 1
        #expect(dotCount == commits.count)
    }

    @Test("Every row carries its commit SHA as an attribute for click handling")
    func rowsHaveShaAttribute() {
        let commits = [commit("abc1234", parents: [])]
        let nodes = GitGraphLayout.layout(commits)
        let html = GitGraphRenderer.html(commits: commits, nodes: nodes)

        #expect(html.contains(#"data-sha="abc1234""#))
    }

    @Test("A commit's subject is HTML-escaped so <script> is text, not markup")
    func subjectIsEscaped() {
        let commits = [commit("a", subject: "fix: <script>evil()</script>")]
        let nodes = GitGraphLayout.layout(commits)
        let html = GitGraphRenderer.html(commits: commits, nodes: nodes)

        // The escaped form must survive; the raw form must not, or a subject can inject.
        #expect(html.contains("&lt;script&gt;"))
        #expect(!html.contains("<script>evil"))
    }

    @Test("Ref labels are rendered as separate badges")
    func refsRenderAsBadges() {
        let commits = [commit("a", refs: ["main", "v1.0"])]
        let nodes = GitGraphLayout.layout(commits)
        let html = GitGraphRenderer.html(commits: commits, nodes: nodes)

        // Each ref should appear inside a `.ref` span; both must be present.
        #expect(html.contains(#"<span class="ref">main</span>"#))
        #expect(html.contains(#"<span class="ref">v1.0</span>"#))
    }

    @Test("A merge commit is drawn with a hollow dot")
    func mergeDotIsHollow() {
        let commits = [
            commit("m", parents: ["a", "b"]),
            commit("a"),
            commit("b"),
        ]
        let nodes = GitGraphLayout.layout(commits)
        let html = GitGraphRenderer.html(commits: commits, nodes: nodes)

        // Presence of a stroked-and-hollow-filled circle is the visual marker.
        #expect(html.contains(#"fill="var(--bg)"#))
    }

    @Test("An empty page still produces a valid document")
    func emptyPage() {
        let html = GitGraphRenderer.html(commits: [], nodes: [])

        #expect(html.hasPrefix("<!DOCTYPE html>"))
    }
}
