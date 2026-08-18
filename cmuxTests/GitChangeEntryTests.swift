import Foundation
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

/// Covers how `git status` output becomes rows in the Git sidebar.
///
/// The list itself is SwiftUI and out of reach here, so the shaping is kept in a value type
/// where it can be pinned: ordering, the path split, and the badge letters.
@Suite("GitChangeEntry")
struct GitChangeEntryTests {
    private let root = "/repo"

    @Test("entries come back in path order")
    func sortedByPath() {
        // `git status` hands back a dictionary. Rendering it unsorted would reshuffle rows on
        // every refresh, and refreshes happen on each directory-watch event.
        let entries = GitChangeEntry.entries(from: [
            "/repo/z.swift": .modified,
            "/repo/a.swift": .added,
            "/repo/m.swift": .deleted,
        ])
        #expect(entries.map(\.path) == ["/repo/a.swift", "/repo/m.swift", "/repo/z.swift"])
    }

    @Test("an empty status yields no entries")
    func emptyStatus() {
        #expect(GitChangeEntry.entries(from: [:]).isEmpty)
    }

    @Test("the file name is the last path component")
    func fileName() {
        let entry = GitChangeEntry(path: "/repo/Sources/App.swift", status: .modified)
        #expect(entry.fileName == "App.swift")
    }

    @Test("a file directly in the root has no directory shown")
    func directoryAtRoot() {
        let entry = GitChangeEntry(path: "/repo/README.md", status: .modified)
        #expect(entry.relativeDirectory(from: root) == nil)
    }

    @Test("a nested file shows its directory relative to the root")
    func nestedDirectory() {
        let entry = GitChangeEntry(path: "/repo/Sources/Panels/App.swift", status: .modified)
        #expect(entry.relativeDirectory(from: root) == "Sources/Panels")
    }

    @Test("a path outside the root falls back to its own directory")
    func directoryOutsideRoot() {
        // Should not happen — the provider filters to the explorer root — but dropping a
        // prefix that is not there would silently mangle the path.
        let entry = GitChangeEntry(path: "/elsewhere/App.swift", status: .modified)
        #expect(entry.relativeDirectory(from: root) == "/elsewhere")
    }

    @Test("badges match what git status --short prints")
    func badges() {
        let cases: [(GitFileStatus, String)] = [
            (.modified, "M"), (.added, "A"), (.deleted, "D"),
            (.renamed, "R"), (.untracked, "?"),
        ]
        for (status, expected) in cases {
            #expect(GitChangeEntry(path: "/repo/f", status: status).badge == expected)
        }
    }

    @Test("all five statuses survive the mapping")
    func allStatusesMapped() {
        let entries = GitChangeEntry.entries(from: [
            "/repo/1": .modified, "/repo/2": .added, "/repo/3": .deleted,
            "/repo/4": .renamed, "/repo/5": .untracked,
        ])
        #expect(entries.count == 5)
        #expect(Set(entries.map(\.badge)) == ["M", "A", "D", "R", "?"])
    }

    @Test("identity is the path, so rows stay put across refreshes")
    func identity() {
        // `ForEach` keys on this. An id that changed per refresh would rebuild every row.
        let entry = GitChangeEntry(path: "/repo/a.swift", status: .modified)
        #expect(entry.id == "/repo/a.swift")
    }
}
