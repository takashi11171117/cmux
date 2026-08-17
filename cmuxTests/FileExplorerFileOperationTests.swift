import Foundation
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

/// Covers the file tree's writing actions.
///
/// These are the only context-menu entries that modify a user's files, so each one is
/// exercised against a real temporary directory rather than a mock: the failure that matters
/// is `FileManager` refusing or overwriting, which a stub would not reproduce.
@Suite("FileExplorerFileOperation")
@MainActor
struct FileExplorerFileOperationTests {
    /// A temporary directory removed when the test ends.
    private final class Sandbox {
        let url: URL

        init() throws {
            url = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("afide-file-op-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }

        deinit {
            try? FileManager.default.removeItem(at: url)
        }

        func write(_ name: String, contents: String = "") throws -> URL {
            let target = url.appendingPathComponent(name)
            try contents.write(to: target, atomically: true, encoding: .utf8)
            return target
        }

        func exists(_ name: String) -> Bool {
            FileManager.default.fileExists(atPath: url.appendingPathComponent(name).path)
        }
    }

    // MARK: - Creating

    @Test("createFile makes an empty file")
    func createFileMakesEmptyFile() throws {
        let sandbox = try Sandbox()
        let created = try FileExplorerFileOperation.createFile(named: "notes.txt", in: sandbox.url)

        #expect(created.lastPathComponent == "notes.txt")
        #expect(sandbox.exists("notes.txt"))
        #expect(try Data(contentsOf: created).isEmpty)
    }

    @Test("createFile refuses to clobber an existing file")
    func createFileRefusesExisting() throws {
        let sandbox = try Sandbox()
        _ = try sandbox.write("notes.txt", contents: "original")

        #expect(throws: FileExplorerFileOperationError.self) {
            _ = try FileExplorerFileOperation.createFile(named: "notes.txt", in: sandbox.url)
        }

        // The point of refusing: the original content survives.
        let survived = try String(contentsOf: sandbox.url.appendingPathComponent("notes.txt"), encoding: .utf8)
        #expect(survived == "original")
    }

    @Test("createDirectory makes a directory")
    func createDirectoryMakesDirectory() throws {
        let sandbox = try Sandbox()
        let created = try FileExplorerFileOperation.createDirectory(named: "src", in: sandbox.url)

        var isDirectory: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: created.path, isDirectory: &isDirectory))
        #expect(isDirectory.boolValue)
    }

    @Test("createDirectory refuses a name already taken by a file")
    func createDirectoryRefusesExistingFile() throws {
        let sandbox = try Sandbox()
        _ = try sandbox.write("src")

        #expect(throws: FileExplorerFileOperationError.self) {
            _ = try FileExplorerFileOperation.createDirectory(named: "src", in: sandbox.url)
        }
    }

    // MARK: - Renaming

    @Test("rename moves the item and keeps its contents")
    func renameKeepsContents() throws {
        let sandbox = try Sandbox()
        let original = try sandbox.write("before.txt", contents: "payload")

        let renamed = try FileExplorerFileOperation.rename(original, to: "after.txt")

        #expect(renamed.lastPathComponent == "after.txt")
        #expect(!sandbox.exists("before.txt"))
        #expect(try String(contentsOf: renamed, encoding: .utf8) == "payload")
    }

    @Test("rename to the same name is a no-op, not a failure")
    func renameToSameNameSucceeds() throws {
        let sandbox = try Sandbox()
        let original = try sandbox.write("same.txt", contents: "payload")

        let result = try FileExplorerFileOperation.rename(original, to: "same.txt")

        #expect(result == original)
        #expect(try String(contentsOf: result, encoding: .utf8) == "payload")
    }

    @Test("rename refuses to overwrite another file")
    func renameRefusesOverwrite() throws {
        let sandbox = try Sandbox()
        let source = try sandbox.write("a.txt", contents: "source")
        _ = try sandbox.write("b.txt", contents: "destination")

        #expect(throws: FileExplorerFileOperationError.self) {
            _ = try FileExplorerFileOperation.rename(source, to: "b.txt")
        }

        // Neither side moved.
        #expect(try String(contentsOf: sandbox.url.appendingPathComponent("a.txt"), encoding: .utf8) == "source")
        #expect(try String(contentsOf: sandbox.url.appendingPathComponent("b.txt"), encoding: .utf8) == "destination")
    }

    // MARK: - Duplicating

    @Test("duplicate suffixes before the extension so the copy opens in the same app")
    func duplicateKeepsExtension() throws {
        let sandbox = try Sandbox()
        let original = try sandbox.write("notes.txt", contents: "payload")

        let copy = try FileExplorerFileOperation.duplicate(original)

        #expect(copy.lastPathComponent == "notes copy.txt")
        #expect(try String(contentsOf: copy, encoding: .utf8) == "payload")
        #expect(sandbox.exists("notes.txt"))
    }

    @Test("duplicate counts up when the copy name is taken")
    func duplicateCountsUp() throws {
        let sandbox = try Sandbox()
        let original = try sandbox.write("notes.txt")

        let first = try FileExplorerFileOperation.duplicate(original)
        let second = try FileExplorerFileOperation.duplicate(original)
        let third = try FileExplorerFileOperation.duplicate(original)

        #expect(first.lastPathComponent == "notes copy.txt")
        #expect(second.lastPathComponent == "notes copy 2.txt")
        #expect(third.lastPathComponent == "notes copy 3.txt")
    }

    @Test("duplicate handles a name with no extension")
    func duplicateWithoutExtension() throws {
        let sandbox = try Sandbox()
        let original = try sandbox.write("LICENSE", contents: "text")

        let copy = try FileExplorerFileOperation.duplicate(original)

        #expect(copy.lastPathComponent == "LICENSE copy")
        #expect(try String(contentsOf: copy, encoding: .utf8) == "text")
    }

    @Test("duplicate copies a directory with its contents")
    func duplicateDirectory() throws {
        let sandbox = try Sandbox()
        let directory = try FileExplorerFileOperation.createDirectory(named: "src", in: sandbox.url)
        try "inner".write(to: directory.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)

        let copy = try FileExplorerFileOperation.duplicate(directory)

        #expect(copy.lastPathComponent == "src copy")
        let inner = try String(contentsOf: copy.appendingPathComponent("a.txt"), encoding: .utf8)
        #expect(inner == "inner")
    }

    // MARK: - Trashing

    @Test("moveToTrash removes the item from its directory without deleting it outright")
    func moveToTrashRemovesFromDirectory() throws {
        let sandbox = try Sandbox()
        let target = try sandbox.write("doomed.txt", contents: "payload")

        let trashed = try FileExplorerFileOperation.moveToTrash(target)

        #expect(!sandbox.exists("doomed.txt"))

        // Recoverable, which is why `trashItem` is used instead of `removeItem`. Clean up so
        // running the suite does not fill the developer's Trash.
        let recovered = try #require(trashed)
        #expect(FileManager.default.fileExists(atPath: recovered.path))
        #expect(try String(contentsOf: recovered, encoding: .utf8) == "payload")
        try? FileManager.default.removeItem(at: recovered)
    }

    @Test("moveToTrash reports failure for a path that does not exist")
    func moveToTrashMissingPathThrows() throws {
        let sandbox = try Sandbox()
        let missing = sandbox.url.appendingPathComponent("never-existed.txt")

        #expect(throws: (any Error).self) {
            _ = try FileExplorerFileOperation.moveToTrash(missing)
        }
    }

    // MARK: - Error text

    @Test("errors carry a message naming the offending file")
    func errorsNameTheFile() {
        let exists = FileExplorerFileOperationError.alreadyExists("notes.txt")
        let failed = FileExplorerFileOperationError.createFailed("notes.txt")

        #expect(exists.errorDescription?.contains("notes.txt") == true)
        #expect(failed.errorDescription?.contains("notes.txt") == true)
    }
}
