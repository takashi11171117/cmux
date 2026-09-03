import Foundation
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

/// How `git status --porcelain=v1`'s XY pair maps to a ``GitEntryStatus``.
///
/// The behaviour these pin down: (1) staged and unstaged are truly independent — an `MM`
/// file lands in both sections of the sidebar, so both sides must be present in the
/// parsed value; (2) untracked (`??`) belongs to the working-tree side alone, not both
/// (git treats `git add` as the only way to move it, which means untracked never has a
/// staged counterpart worth showing); (3) an empty space on either side means "no change
/// on that side", not "modified" or "added".
@Suite("Git status XY parsing")
struct GitStatusProviderXYParsingTests {
    // MARK: Staged-only

    @Test("`M ` is a staged modification only")
    func stagedModifiedOnly() {
        let s = GitStatusProvider.parseXY(index: "M", workTree: " ")
        #expect(s == GitEntryStatus(staged: .modified, unstaged: nil))
    }

    @Test("`A ` is a staged addition only")
    func stagedAddedOnly() {
        let s = GitStatusProvider.parseXY(index: "A", workTree: " ")
        #expect(s == GitEntryStatus(staged: .added, unstaged: nil))
    }

    @Test("`D ` is a staged deletion only")
    func stagedDeletedOnly() {
        let s = GitStatusProvider.parseXY(index: "D", workTree: " ")
        #expect(s == GitEntryStatus(staged: .deleted, unstaged: nil))
    }

    @Test("`R ` is a staged rename only")
    func stagedRenamedOnly() {
        let s = GitStatusProvider.parseXY(index: "R", workTree: " ")
        #expect(s == GitEntryStatus(staged: .renamed, unstaged: nil))
    }

    // MARK: Unstaged-only

    @Test("` M` is an unstaged modification only")
    func unstagedModifiedOnly() {
        let s = GitStatusProvider.parseXY(index: " ", workTree: "M")
        #expect(s == GitEntryStatus(staged: nil, unstaged: .modified))
    }

    @Test("` D` is an unstaged deletion only")
    func unstagedDeletedOnly() {
        let s = GitStatusProvider.parseXY(index: " ", workTree: "D")
        #expect(s == GitEntryStatus(staged: nil, unstaged: .deleted))
    }

    // MARK: Both sides

    @Test("`MM` is staged modified plus unstaged modified — must appear in both sections")
    func stagedAndUnstagedModified() {
        let s = GitStatusProvider.parseXY(index: "M", workTree: "M")
        #expect(s == GitEntryStatus(staged: .modified, unstaged: .modified))
    }

    @Test("`AM` is staged addition plus unstaged modification")
    func stagedAddedThenUnstagedModified() {
        let s = GitStatusProvider.parseXY(index: "A", workTree: "M")
        #expect(s == GitEntryStatus(staged: .added, unstaged: .modified))
    }

    // MARK: Untracked

    @Test("`??` maps to unstaged-side untracked, not both sides")
    func untrackedGoesToUnstagedSideOnly() {
        // Regression against the naive "map each character" implementation, which would
        // produce `staged: .untracked, unstaged: .untracked` and light both sections up
        // for a file that has never been added.
        let s = GitStatusProvider.parseXY(index: "?", workTree: "?")
        #expect(s == GitEntryStatus(staged: nil, unstaged: .untracked))
    }

    // MARK: Edge cases

    @Test("`  ` (both blank) yields nil — no change to report")
    func bothBlankYieldsNil() {
        #expect(GitStatusProvider.parseXY(index: " ", workTree: " ") == nil)
    }

    @Test("`T` (type change) maps to modified")
    func typeChangeMapsToModified() {
        let staged = GitStatusProvider.parseXY(index: "T", workTree: " ")
        let unstaged = GitStatusProvider.parseXY(index: " ", workTree: "T")
        #expect(staged?.staged == .modified)
        #expect(unstaged?.unstaged == .modified)
    }

    @Test("`U` (unmerged) maps to modified so the sidebar shows the conflict as a change")
    func unmergedMapsToModified() {
        // Conflict-resolution UI is not in scope here (see docs/fork/git-stage/01
        // 4.2). The row still needs to appear so the user knows the file exists.
        let s = GitStatusProvider.parseXY(index: "U", workTree: "U")
        #expect(s?.displayStatus == .modified)
    }

    @Test("Parsed file entries are not directory markers")
    func fileEntriesAreNotDirectoryMarkers() {
        let s = GitStatusProvider.parseXY(index: "M", workTree: " ")
        #expect(s?.isDirectoryMarker == false)
    }

    @Test("A directory marker is flagged so the Git tab can drop it")
    func directoryMarkerIsFlagged() {
        // The provider synthesizes one entry per ancestor folder for the outline's
        // colour marks. Without the flag those leaked into the Git tab as file rows
        // (`M src` next to the real `src/` folder node).
        let marker = GitEntryStatus(staged: nil, unstaged: .modified, isDirectoryMarker: true)
        #expect(marker.isDirectoryMarker)
        #expect(marker.displayStatus == .modified)
    }

    @Test("displayStatus prefers unstaged so MM reads as \"modified\" in the file tree")
    func displayStatusPrefersUnstaged() {
        let mm = GitEntryStatus(staged: .modified, unstaged: .modified)
        #expect(mm.displayStatus == .modified)

        let stagedOnly = GitEntryStatus(staged: .added, unstaged: nil)
        #expect(stagedOnly.displayStatus == .added)

        let unstagedWinsOverStaged = GitEntryStatus(staged: .added, unstaged: .modified)
        #expect(unstagedWinsOverStaged.displayStatus == .modified)
    }
}
