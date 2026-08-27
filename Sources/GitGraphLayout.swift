import Foundation

/// One commit's position in the rendered graph.
///
/// A value type per commit, in the same order as the input list. The graph view walks these
/// left-to-right and draws lanes as vertical strips; incoming lines are the ones drawn
/// *upward* into the parent row, so this row carries where its parents are relative to
/// itself.
struct GitGraphNode: Equatable, Sendable {
    /// Which lane the commit's dot sits in (0 = leftmost).
    let lane: Int
    /// The set of lanes that pass through this row without terminating in it. Rendering
    /// draws a vertical line through each so a long-lived branch is a continuous stripe.
    let passThroughLanes: [Int]
    /// For each parent of this commit, where its dot ends up.
    ///
    /// Ordered the same as ``GitCommitLine/parents``. The first entry is the "first parent"
    /// — for a merge, that is the branch tip this commit sat on before merging in the
    /// second parent. Rendering distinguishes them so a merge reads as one arm coming from
    /// the same lane and another arm swooping in from the side.
    let parentEdges: [Edge]

    /// A line from this commit's dot to one of its parents' dots.
    struct Edge: Equatable, Sendable {
        /// Lane the parent ends up in.
        let parentLane: Int
        /// Rows down to the parent (>= 1 for a normal parent; may skip intermediate rows
        /// that do not include the parent SHA, though the current layout does not).
        let rowsDown: Int
    }
}

/// Deterministically assigns a lane to every commit in a page of history.
///
/// Rules:
///
///  - Iterate the input in the order it came from `git log` (newest first).
///  - The first parent of a commit stays in the same lane. This keeps the mainline
///    straight rather than zig-zagging across every merge, matching how tools like Tower
///    and `git log --graph` present the history.
///  - Additional parents (merges) take the leftmost currently-free lane.
///  - A commit itself takes the lane its own SHA was previously reserved in (by a
///    younger child), or the leftmost free lane if it is a tip.
///  - Once the last child of a lane has been placed, the lane is released and available
///    to the next fresh commit.
///
/// The layout is a value type because the graph output is a pure function of the input
/// commit sequence — no repository access, no clocks. That makes it testable with hand-
/// written trees, which is the point of the split from ``GitGraphView``.
enum GitGraphLayout {
    /// Builds one node per commit.
    ///
    /// - Parameter commits: The page, newest first.
    /// - Returns: One node per input, in the same order.
    static func layout(_ commits: [GitCommitLine]) -> [GitGraphNode] {
        // A slot is "the lane index; the sha we expect to appear there next". `nil` means
        // the lane is free. We hand out lanes by scanning from index 0 for the first free
        // slot, which keeps the leftmost lanes packed even after merges terminate.
        var lanes: [String?] = []

        func reserveLane(for sha: String) -> Int {
            // Reuse if a child has already reserved this sha's lane.
            if let existing = lanes.firstIndex(where: { $0 == sha }) {
                return existing
            }
            if let free = lanes.firstIndex(where: { $0 == nil }) {
                lanes[free] = sha
                return free
            }
            lanes.append(sha)
            return lanes.count - 1
        }

        var nodes: [GitGraphNode] = []
        nodes.reserveCapacity(commits.count)

        for commit in commits {
            let lane = reserveLane(for: commit.sha)
            // Drop the reservation for this sha before assigning parent lanes: otherwise a
            // parent that happens to share a sha with a still-open lane would collide.
            lanes[lane] = nil

            var edges: [GitGraphNode.Edge] = []
            edges.reserveCapacity(commit.parents.count)
            for (index, parent) in commit.parents.enumerated() {
                let parentLane: Int
                if index == 0 {
                    // First parent inherits the current commit's lane — the mainline stays
                    // straight. If some other reservation already sat in that lane, we let
                    // it move rather than overwrite.
                    if let existing = lanes.firstIndex(where: { $0 == parent }) {
                        parentLane = existing
                    } else if lanes.indices.contains(lane), lanes[lane] == nil {
                        lanes[lane] = parent
                        parentLane = lane
                    } else {
                        parentLane = reserveLane(for: parent)
                    }
                } else {
                    parentLane = reserveLane(for: parent)
                }
                edges.append(GitGraphNode.Edge(parentLane: parentLane, rowsDown: 1))
            }

            // Trim trailing empties so `passThroughLanes` reflects a stable rightmost edge.
            while let last = lanes.last, last == nil { lanes.removeLast() }

            let passThrough = lanes.indices.filter { lanes[$0] != nil && $0 != lane }
            nodes.append(GitGraphNode(
                lane: lane,
                passThroughLanes: passThrough,
                parentEdges: edges
            ))
        }
        return nodes
    }
}
