import Foundation
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

/// Which directory an editor is handed as "the project" for a file.
///
/// The behaviour this exists for: opening a file on its own gives the editor no project at all —
/// no sibling files, no search, no symbol index.
@Suite("Editor project root")
struct EditorProjectRootTests {
    @Test("The deepest containing directory wins")
    func deepestCandidateWins() {
        let root = EditorProjectRoot(
            filePath: "/repo/app/Sources/App.swift",
            candidates: ["/repo", "/repo/app"]
        )

        // A workspace opened on a monorepo subdirectory should not drag in the whole repository.
        #expect(root?.path == "/repo/app")
    }

    @Test("Order of the candidates does not matter")
    func candidateOrderIsIrrelevant() {
        let root = EditorProjectRoot(
            filePath: "/repo/app/Sources/App.swift",
            candidates: ["/repo/app", "/repo"]
        )

        #expect(root?.path == "/repo/app")
    }

    @Test("A candidate that does not contain the file is ignored")
    func nonContainingCandidateIsIgnored() {
        let root = EditorProjectRoot(
            filePath: "/repo/app/Sources/App.swift",
            candidates: ["/elsewhere/deeper/still", "/repo"]
        )

        // The deeper path loses because the file is not inside it.
        #expect(root?.path == "/repo")
    }

    @Test("A sibling directory sharing a name prefix is not a parent")
    func siblingWithSharedPrefixIsNotAParent() {
        // `/repo/ab` is a string prefix of `/repo/abc/App.swift` but contains nothing of it.
        let root = EditorProjectRoot(
            filePath: "/repo/abc/App.swift",
            candidates: ["/repo/ab"]
        )

        #expect(root == nil)
    }

    @Test("The file's own directory path is not a project for it")
    func fileItselfIsNotItsProject() {
        let root = EditorProjectRoot(
            filePath: "/repo/App.swift",
            candidates: ["/repo/App.swift"]
        )

        #expect(root == nil)
    }

    @Test("No candidate containing the file means no project")
    func noContainingCandidateYieldsNil() {
        let root = EditorProjectRoot(
            filePath: "/somewhere/else/App.swift",
            candidates: ["/repo", "/other"]
        )

        #expect(root == nil)
    }

    @Test("Empty and blank candidates are skipped")
    func blankCandidatesAreSkipped() {
        let root = EditorProjectRoot(
            filePath: "/repo/App.swift",
            candidates: ["", "   ", "/repo"]
        )

        #expect(root?.path == "/repo")
    }

    @Test("No candidates at all means no project")
    func emptyCandidateListYieldsNil() {
        #expect(EditorProjectRoot(filePath: "/repo/App.swift", candidates: []) == nil)
    }

    @Test("A trailing slash spells the same directory")
    func trailingSlashIsTheSameDirectory() {
        let root = EditorProjectRoot(
            filePath: "/repo/app/App.swift",
            candidates: ["/repo/app/"]
        )

        #expect(root?.path == "/repo/app")
    }
}

/// Which applications are handed a folder alongside the file.
@Suite("Project opening editor")
struct ProjectOpeningEditorTests {
    private func editor(withMarkerIn bundlePaths: [String]) -> ProjectOpeningEditor {
        let markers = Set(bundlePaths.map { "\($0)/\(ProjectOpeningEditor.markerPath)" })
        return ProjectOpeningEditor(fileExistsAtPath: { markers.contains($0) })
    }

    @Test("An editor carrying the VS Code marker takes a project folder")
    func vsCodeFamilyOpensFolders() {
        let subject = editor(withMarkerIn: ["/Applications/Visual Studio Code.app"])

        #expect(subject.opensFolderAsProject(
            applicationURL: URL(fileURLWithPath: "/Applications/Visual Studio Code.app")
        ))
    }

    @Test("A fork nobody listed is detected by the same marker")
    func unlistedForkIsDetected() {
        // The point of detecting the family by its own bundle contents rather than by a list of
        // bundle identifiers: a fork works without anyone adding it here.
        let subject = editor(withMarkerIn: ["/Applications/Some New Fork.app"])

        #expect(subject.opensFolderAsProject(
            applicationURL: URL(fileURLWithPath: "/Applications/Some New Fork.app")
        ))
    }

    @Test("An application without the marker is left alone")
    func otherApplicationsGetOnlyTheFile() {
        let subject = editor(withMarkerIn: ["/Applications/Visual Studio Code.app"])

        #expect(!subject.opensFolderAsProject(
            applicationURL: URL(fileURLWithPath: "/Applications/Preview.app")
        ))
        #expect(!subject.opensFolderAsProject(
            applicationURL: URL(fileURLWithPath: "/Applications/Xcode.app")
        ))
    }
}
