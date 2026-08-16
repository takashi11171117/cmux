import Foundation
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

@MainActor
@Suite("FilePreviewSaveConflictCoordinator")
struct FilePreviewSaveConflictCoordinatorTests {
    /// Stand-in for a panel, recording whether a reload was requested.
    private final class StubPanel: FilePreviewSaveConflictResolving {
        var isDirty: Bool
        private(set) var reloadCount = 0

        init(isDirty: Bool) { self.isDirty = isDirty }

        func reloadDiscardingLocalEdits() {
            reloadCount += 1
            isDirty = false
        }
    }

    private let fixedNow = Date(timeIntervalSince1970: 1_700_000_000)

    @Test("a genuine external change while dirty raises a conflict")
    func externalChangeRaisesConflict() {
        let coordinator = FilePreviewSaveConflictCoordinator()
        coordinator.noteDiskContentWhileDirty(
            filePath: "/tmp/a.swift",
            diskContent: "agent wrote this",
            previousDiskContent: "original",
            bufferContent: "my unsaved edits",
            now: fixedNow
        )
        #expect(coordinator.pending?.filePath == "/tmp/a.swift")
        #expect(coordinator.pending?.diskContent == "agent wrote this")
        #expect(coordinator.pending?.detectedAt == fixedNow)
    }

    @Test("an unchanged disk version raises nothing")
    func unchangedDiskRaisesNothing() {
        // This is what keeps the save-failure path quiet: a failed write leaves disk exactly
        // as it was, and that path re-enters the same reload.
        let coordinator = FilePreviewSaveConflictCoordinator()
        coordinator.noteDiskContentWhileDirty(
            filePath: "/tmp/a.swift",
            diskContent: "same",
            previousDiskContent: "same",
            bufferContent: "my unsaved edits",
            now: fixedNow
        )
        #expect(coordinator.pending == nil)
    }

    @Test("disk matching the buffer raises nothing")
    func echoOfOwnSaveRaisesNothing() {
        // Our own save coming back through the file watcher. Defined without consulting
        // isSaving because FilePreviewPanel guards on it and MarkdownPanel does not.
        let coordinator = FilePreviewSaveConflictCoordinator()
        coordinator.noteDiskContentWhileDirty(
            filePath: "/tmp/a.swift",
            diskContent: "identical text",
            previousDiskContent: "older text",
            bufferContent: "identical text",
            now: fixedNow
        )
        #expect(coordinator.pending == nil)
    }

    @Test("a second conflict replaces the first rather than queueing")
    func latestConflictWins() {
        let coordinator = FilePreviewSaveConflictCoordinator()
        coordinator.noteDiskContentWhileDirty(
            filePath: "/tmp/a.swift", diskContent: "v2", previousDiskContent: "v1",
            bufferContent: "mine", now: fixedNow
        )
        coordinator.noteDiskContentWhileDirty(
            filePath: "/tmp/a.swift", diskContent: "v3", previousDiskContent: "v2",
            bufferContent: "mine", now: fixedNow.addingTimeInterval(1)
        )
        #expect(coordinator.pending?.diskContent == "v3")
        #expect(coordinator.pending?.detectedAt == fixedNow.addingTimeInterval(1))
    }

    @Test("reload asks the panel to drop local edits")
    func reloadDiscardsEdits() {
        let coordinator = FilePreviewSaveConflictCoordinator()
        let panel = StubPanel(isDirty: true)
        coordinator.noteDiskContentWhileDirty(
            filePath: "/tmp/a.swift", diskContent: "v2", previousDiskContent: "v1",
            bufferContent: "mine", now: fixedNow
        )

        coordinator.resolve(.reload, on: panel)

        #expect(panel.reloadCount == 1)
        #expect(panel.isDirty == false)
        #expect(coordinator.pending == nil)
    }

    @Test("keep mine changes nothing except dismissing the prompt")
    func keepMineLeavesStateAlone() {
        let coordinator = FilePreviewSaveConflictCoordinator()
        let panel = StubPanel(isDirty: true)
        coordinator.noteDiskContentWhileDirty(
            filePath: "/tmp/a.swift", diskContent: "v2", previousDiskContent: "v1",
            bufferContent: "mine", now: fixedNow
        )

        coordinator.resolve(.keepMine, on: panel)

        #expect(panel.reloadCount == 0)
        #expect(panel.isDirty, "the buffer must stay dirty so the next save still writes it")
        #expect(coordinator.pending == nil)
    }

    @Test("compare keeps the conflict pending until it is implemented")
    func compareKeepsConflictPending() {
        // Clearing here would silently discard the conflict while showing nothing.
        let coordinator = FilePreviewSaveConflictCoordinator()
        let panel = StubPanel(isDirty: true)
        coordinator.noteDiskContentWhileDirty(
            filePath: "/tmp/a.swift", diskContent: "v2", previousDiskContent: "v1",
            bufferContent: "mine", now: fixedNow
        )

        coordinator.resolve(.compare, on: panel)

        #expect(coordinator.pending != nil)
        #expect(panel.reloadCount == 0)
    }

    @Test("clear drops the conflict for a file that disappeared")
    func clearDropsConflict() {
        let coordinator = FilePreviewSaveConflictCoordinator()
        coordinator.noteDiskContentWhileDirty(
            filePath: "/tmp/a.swift", diskContent: "v2", previousDiskContent: "v1",
            bufferContent: "mine", now: fixedNow
        )
        coordinator.clear()
        #expect(coordinator.pending == nil)
    }
}
