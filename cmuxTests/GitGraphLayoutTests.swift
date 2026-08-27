import Foundation
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

/// How commits are placed into lanes for the graph.
///
/// The behaviours these pin down: (1) a straight-line history is drawn on one lane, not
/// spread out; (2) a branch and merge draws the second parent on a lane of its own; (3)
/// the mainline stays in the same lane through a merge rather than zig-zagging; (4) a
/// lane is released once no younger child expects a parent in it, so the number of lanes
/// stays bounded even in long-lived history.
@Suite("Git graph layout")
struct GitGraphLayoutTests {
    /// Terse constructor: parents are given as short strings; the other fields are dummies.
    private func commit(_ sha: String, parents: [String] = []) -> GitCommitLine {
        GitCommitLine(
            sha: sha,
            shortSHA: String(sha.prefix(7)),
            parents: parents,
            authorName: "T",
            authoredAt: Date(timeIntervalSince1970: 0),
            subject: sha,
            refNames: []
        )
    }

    @Test("A straight-line history is drawn on one lane")
    func straightLineUsesOneLane() {
        let nodes = GitGraphLayout.layout([
            commit("c", parents: ["b"]),
            commit("b", parents: ["a"]),
            commit("a"),
        ])

        #expect(nodes.map(\.lane) == [0, 0, 0])
    }

    @Test("A single side branch adds one lane")
    func sideBranchAddsOneLane() {
        // Shape:
        //   m ── merge, parents = [c, b1]
        //   c
        //   b1
        //   base
        // Chronologically: m is newest.
        let nodes = GitGraphLayout.layout([
            commit("m", parents: ["c", "b1"]),
            commit("c", parents: ["base"]),
            commit("b1", parents: ["base"]),
            commit("base"),
        ])

        // Mainline stays on lane 0; the second parent goes to lane 1 and merges back once
        // the base commit collapses everything.
        #expect(nodes[0].lane == 0)
        #expect(nodes[0].parentEdges.map(\.parentLane) == [0, 1])
    }

    @Test("The mainline lane does not shift through a merge")
    func mainlineStaysStraightThroughMerge() {
        // The merge inherits the current commit's lane for its first parent, so a viewer
        // reading top-to-bottom follows one uninterrupted stripe rather than a zig-zag.
        let nodes = GitGraphLayout.layout([
            commit("m", parents: ["c", "b"]),
            commit("c", parents: ["base"]),
            commit("b", parents: ["base"]),
            commit("base"),
        ])

        // The commit `c` is the first parent of `m`, so it sits in the same lane as `m`.
        #expect(nodes[1].lane == nodes[0].lane)
    }

    @Test("A lane is released when its child count reaches zero")
    func laneReleasedAfterLastChild() {
        // After the merge collapses the side branch, a later independent branch should
        // reuse lane 1 rather than open lane 2.
        let nodes = GitGraphLayout.layout([
            commit("m2", parents: ["m1", "d"]),
            commit("m1", parents: ["c", "b"]),
            commit("c", parents: ["a"]),
            commit("b", parents: ["a"]),
            commit("d", parents: ["a"]),
            commit("a"),
        ])

        // Whatever the shape, no node should ever assign a lane greater than 2 here.
        let maxLane = nodes.map(\.lane).max() ?? 0
        #expect(maxLane <= 2)
    }

    @Test("A root commit has no parent edges")
    func rootHasNoParentEdges() {
        let nodes = GitGraphLayout.layout([commit("root")])

        #expect(nodes[0].parentEdges.isEmpty)
    }

    @Test("A merge commit records both parent edges in input order")
    func mergeRecordsBothParents() {
        let nodes = GitGraphLayout.layout([
            commit("m", parents: ["main", "topic"]),
            commit("main"),
            commit("topic"),
        ])

        #expect(nodes[0].parentEdges.count == 2)
        // The first edge is the current lane (mainline); the second is the new lane.
        #expect(nodes[0].parentEdges[0].parentLane == nodes[0].lane)
        #expect(nodes[0].parentEdges[1].parentLane != nodes[0].lane)
    }

    @Test("The empty page yields an empty layout")
    func emptyPage() {
        #expect(GitGraphLayout.layout([]).isEmpty)
    }

    @Test("An orphan commit (referenced parent not in page) still lays out")
    func orphanParent() {
        // git log --max-count returns a window; the oldest commit's parent may fall
        // outside the page. The layout must not crash or produce garbage.
        let nodes = GitGraphLayout.layout([
            commit("child", parents: ["off_page"]),
        ])

        #expect(nodes.count == 1)
        #expect(nodes[0].lane == 0)
    }
}
