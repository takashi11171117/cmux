import Foundation

/// Turns a page of commits + their lane layout into a self-contained HTML document.
///
/// A value type so the SVG and CSS output are testable without launching a WebView. The
/// page is one big `<svg>` inline plus a right-hand column of commit metadata; laying the
/// two out in a CSS grid keeps the row heights locked together as the WebView reflows.
///
/// Nothing about the WebView itself is here — the caller writes the returned string to
/// a `file://` URL and hands it to the code-review column. That URL stays constant per
/// workspace, so `CodeReviewPanelState.showBrowser` matches it exactly and reuses one tab
/// (Sources/CodeReviewPanelState.swift:127-134).
enum GitGraphRenderer {
    /// Space between lanes, in CSS pixels.
    static let laneWidth: CGFloat = 16
    /// Vertical distance between commit rows, in CSS pixels.
    static let rowHeight: CGFloat = 22
    /// Radius of the commit dot.
    static let dotRadius: CGFloat = 4

    /// Palette used to distinguish lanes. `Color.lane(_:)` in the sidebar draws from the
    /// same list, indexed by lane number modulo count — a mainline branch always takes
    /// lane 0, so its colour is stable regardless of what other lanes exist.
    static let laneColors: [String] = [
        "#4c9ce6", "#e6884c", "#7cb342", "#c85c8e",
        "#8e7cc3", "#c9a227", "#4dd0e1", "#d84a4a",
    ]

    private static func laneColor(_ lane: Int) -> String {
        laneColors[abs(lane) % laneColors.count]
    }

    /// Builds the HTML.
    ///
    /// - Parameters:
    ///   - commits: The page, newest first.
    ///   - nodes: Layout for the same page — same length, same order.
    /// - Returns: A `<!DOCTYPE html>`-prefixed document ready to be written to disk.
    static func html(commits: [GitCommitLine], nodes: [GitGraphNode]) -> String {
        precondition(commits.count == nodes.count, "commits and nodes must be parallel")
        let laneCount = (nodes.flatMap { [$0.lane] + $0.passThroughLanes + $0.parentEdges.map(\.parentLane) }.max() ?? 0) + 1
        let svgWidth = CGFloat(laneCount) * laneWidth + laneWidth
        let svgHeight = CGFloat(commits.count) * rowHeight + rowHeight
        let body = svg(commits: commits, nodes: nodes, width: svgWidth, height: svgHeight)
            + rows(commits: commits, nodes: nodes)
        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <title>Git history</title>
        <style>
        \(Self.css)
        </style>
        </head>
        <body>
        <div class="graph">
        \(body)
        </div>
        </body>
        </html>
        """
    }

    private static let css = """
    :root {
        color-scheme: light dark;
        --fg: #ddd;
        --fg-secondary: rgba(221, 221, 221, 0.65);
        --bg: #1e1e1e;
        --row-hover: rgba(255, 255, 255, 0.06);
        --ref-bg: rgba(255, 255, 255, 0.12);
    }
    @media (prefers-color-scheme: light) {
        :root { --fg: #222; --fg-secondary: rgba(0,0,0,0.55); --bg: #fafafa;
                --row-hover: rgba(0, 0, 0, 0.05); --ref-bg: rgba(0, 0, 0, 0.08); }
    }
    body { margin: 0; padding: 0; background: var(--bg); color: var(--fg);
           font: 12px -apple-system, sans-serif; }
    .graph { display: grid; grid-template-columns: max-content 1fr; }
    svg.lanes { display: block; }
    .rows { display: flex; flex-direction: column; }
    .row { display: flex; align-items: center; gap: 6px; padding: 0 10px;
           height: \(Int(rowHeight))px; box-sizing: border-box; cursor: pointer; }
    .row:hover { background: var(--row-hover); }
    .sha { font-family: ui-monospace, "SF Mono", Menlo, monospace; opacity: 0.75; min-width: 60px; }
    .subject { flex: 1 1 auto; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
    .refs { display: inline-flex; gap: 4px; margin-right: 4px; }
    .ref { background: var(--ref-bg); padding: 0 5px; border-radius: 3px; font-size: 10px;
           white-space: nowrap; }
    .author, .date { color: var(--fg-secondary); font-size: 10px; }
    """

    private static func svg(
        commits: [GitCommitLine],
        nodes: [GitGraphNode],
        width: CGFloat,
        height: CGFloat
    ) -> String {
        var lines: [String] = []
        lines.append(#"<svg class="lanes" width="\#(fmt(width))" height="\#(fmt(height))" viewBox="0 0 \#(fmt(width)) \#(fmt(height))" xmlns="http://www.w3.org/2000/svg">"#)
        for (index, node) in nodes.enumerated() {
            let y = CGFloat(index) * rowHeight + rowHeight / 2
            // Pass-through lanes: vertical line the full row height.
            for lane in node.passThroughLanes {
                let x = laneCenterX(lane)
                let color = laneColor(lane)
                lines.append(#"<line x1="\#(fmt(x))" y1="\#(fmt(y - rowHeight/2))" x2="\#(fmt(x))" y2="\#(fmt(y + rowHeight/2))" stroke="\#(color)" stroke-width="1.5"/>"#)
            }
            // Parent edges: dot to parent (one row down).
            let ownX = laneCenterX(node.lane)
            for edge in node.parentEdges {
                let px = laneCenterX(edge.parentLane)
                let py = y + rowHeight
                if px == ownX {
                    lines.append(#"<line x1="\#(fmt(ownX))" y1="\#(fmt(y))" x2="\#(fmt(px))" y2="\#(fmt(py))" stroke="\#(laneColor(node.lane))" stroke-width="1.5"/>"#)
                } else {
                    // Bezier so the branch curves rather than kinks.
                    let midY = y + rowHeight / 2
                    let d = "M \(fmt(ownX)) \(fmt(y)) C \(fmt(ownX)) \(fmt(midY)) \(fmt(px)) \(fmt(midY)) \(fmt(px)) \(fmt(py))"
                    lines.append(#"<path d="\#(d)" fill="none" stroke="\#(laneColor(edge.parentLane))" stroke-width="1.5"/>"#)
                }
            }
            // The dot itself, on top.
            let dotColor = laneColor(node.lane)
            let stroke = commits[index].isMerge ? #" stroke="\#(dotColor)" stroke-width="1.5" fill="var(--bg)""# : #" fill="\#(dotColor)""#
            lines.append(#"<circle cx="\#(fmt(ownX))" cy="\#(fmt(y))" r="\#(fmt(dotRadius))" \#(stroke)/>"#)
        }
        lines.append("</svg>")
        return lines.joined(separator: "\n")
    }

    private static func rows(commits: [GitCommitLine], nodes: [GitGraphNode]) -> String {
        var lines: [String] = ["<div class=\"rows\">"]
        for (index, commit) in commits.enumerated() {
            let refs = commit.refNames.map { #"<span class="ref">\#(escape($0))</span>"# }.joined()
            let refsBlock = refs.isEmpty ? "" : #"<span class="refs">\#(refs)</span>"#
            let relative = GitCommitRelativeDate.string(from: commit.authoredAt)
            _ = nodes[index]
            lines.append("""
            <div class="row" data-sha="\(commit.sha)">
                <span class="sha">\(commit.shortSHA)</span>
                \(refsBlock)<span class="subject">\(escape(commit.subject))</span>
                <span class="author">\(escape(commit.authorName))</span>
                <span class="date">\(escape(relative))</span>
            </div>
            """)
        }
        lines.append("</div>")
        return lines.joined(separator: "\n")
    }

    private static func laneCenterX(_ lane: Int) -> CGFloat {
        laneWidth / 2 + CGFloat(lane) * laneWidth
    }

    private static func fmt(_ value: CGFloat) -> String {
        // Round to 1 decimal so hand-written test expectations stay reasonable.
        String(format: "%.1f", value)
    }

    private static func escape(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
}
