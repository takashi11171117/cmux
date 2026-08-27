import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

/// How the Git sidebar orders and nests its rows.
///
/// The behaviour these pin down: the flat list this replaced was sorted by full path while the
/// row showed the file name first, so a correctly sorted list read as an unordered one.
@Suite("Git change tree rows")
struct GitChangeTreeRowTests {
    private let root = "/repo"

    private func entry(_ path: String, _ status: GitFileStatus = .modified) -> GitChangeEntry {
        GitChangeEntry(path: path, status: status)
    }

    private func names(_ rows: [GitChangeTreeRow]) -> [String] {
        rows.map { row in
            switch row.kind {
            case .folder: return "\(String(repeating: "  ", count: row.depth))\(row.name)/"
            case .file: return "\(String(repeating: "  ", count: row.depth))\(row.name)"
            }
        }
    }

    @Test("Directories are grouped, and come before the files beside them")
    func directoriesGroupAndPrecedeFiles() {
        let rows = GitChangeTreeRow.rows(
            entries: [
                entry("/repo/Makefile"),
                entry("/repo/Sources/App.swift"),
                entry("/repo/README.md"),
                entry("/repo/Sources/View.swift"),
            ],
            root: root,
            collapsedFolders: []
        )

        #expect(names(rows) == [
            "Sources/",
            "  App.swift",
            "  View.swift",
            "Makefile",
            "README.md",
        ])
    }

    @Test("A directory holding only one directory is joined into a single row")
    func singleChildDirectoryChainsCompact() {
        let rows = GitChangeTreeRow.rows(
            entries: [entry("/repo/docs/fork/git/README.md")],
            root: root,
            collapsedFolders: []
        )

        #expect(names(rows) == ["docs/fork/git/", "  README.md"])
    }

    @Test("A chain stops compacting where the tree actually branches")
    func compactionStopsAtABranch() {
        let rows = GitChangeTreeRow.rows(
            entries: [
                entry("/repo/docs/fork/a.md"),
                entry("/repo/docs/fork/git/b.md"),
            ],
            root: root,
            collapsedFolders: []
        )

        #expect(names(rows) == ["docs/fork/", "  git/", "    b.md", "  a.md"])
    }

    @Test("A collapsed folder hides its contents but still counts them")
    func collapsedFolderHidesContentsAndKeepsCount() {
        let rows = GitChangeTreeRow.rows(
            entries: [
                entry("/repo/Sources/App.swift"),
                entry("/repo/Sources/Nested/View.swift"),
            ],
            root: root,
            collapsedFolders: ["Sources"]
        )

        #expect(names(rows) == ["Sources/"])
        #expect(rows.first?.kind == .folder(isCollapsed: true, changeCount: 2))
    }

    @Test("A collapse id left behind by a deleted folder changes nothing")
    func staleCollapseIdIsIgnored() {
        let rows = GitChangeTreeRow.rows(
            entries: [entry("/repo/Sources/App.swift")],
            root: root,
            collapsedFolders: ["Removed/Gone"]
        )

        #expect(names(rows) == ["Sources/", "  App.swift"])
    }

    @Test("Ordering ignores case, so it matches how the names are read")
    func orderingIsCaseInsensitive() {
        let rows = GitChangeTreeRow.rows(
            entries: [
                entry("/repo/zeta.md"),
                entry("/repo/Alpha.md"),
                entry("/repo/beta.md"),
            ],
            root: root,
            collapsedFolders: []
        )

        #expect(names(rows) == ["Alpha.md", "beta.md", "zeta.md"])
    }

    @Test("Rows are ordered the way they are read, top to bottom")
    func rowOrderMatchesReadingOrder() {
        // The exact shape the flat list got wrong: root files were scattered between
        // directories because the sort key was the full path, not the visible name.
        let rows = GitChangeTreeRow.rows(
            entries: [
                entry("/repo/docs/fork/memo.md"),
                entry("/repo/Makefile"),
                entry("/repo/Resources/Info.plist"),
                entry("/repo/Sources/App.swift"),
                entry("/repo/README.md"),
            ],
            root: root,
            collapsedFolders: []
        )

        #expect(names(rows) == [
            "docs/fork/",
            "  memo.md",
            "Resources/",
            "  Info.plist",
            "Sources/",
            "  App.swift",
            "Makefile",
            "README.md",
        ])
    }

    @Test("Files keep the status the row draws its badge from")
    func filesCarryTheirStatus() {
        let rows = GitChangeTreeRow.rows(
            entries: [entry("/repo/Sources/New.swift", .untracked)],
            root: root,
            collapsedFolders: []
        )

        #expect(rows.last?.kind == .file(entry("/repo/Sources/New.swift", .untracked)))
    }
}
