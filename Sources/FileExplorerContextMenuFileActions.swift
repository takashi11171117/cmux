import AppKit
import Foundation
import QuickLookUI

/// The file tree's context-menu actions beyond opening and copying paths.
///
/// Kept out of `FileExplorerPanelView` because these are the tree's only *writing* actions —
/// creating, renaming, duplicating, trashing — and what the tree can do to a user's files
/// should be readable in one place rather than spread through a view file.
///
/// Deletion goes to the Trash via `NSWorkspace.recycle`, never `removeItem`, so an
/// accidental invocation is recoverable from the Finder.
@MainActor
enum FileExplorerFileOperation {
    /// Creates an empty file inside `directory`, returning its URL.
    ///
    /// - Parameters:
    ///   - name: File name, as typed by the user.
    ///   - directory: Directory to create it in.
    /// - Returns: The created file's URL.
    /// - Throws: ``FileExplorerFileOperationError/alreadyExists`` if the name is taken, or
    ///   any error `FileManager` raises.
    static func createFile(named name: String, in directory: URL) throws -> URL {
        let url = directory.appendingPathComponent(name)
        guard !FileManager.default.fileExists(atPath: url.path) else {
            throw FileExplorerFileOperationError.alreadyExists(name)
        }
        guard FileManager.default.createFile(atPath: url.path, contents: Data()) else {
            throw FileExplorerFileOperationError.createFailed(name)
        }
        return url
    }

    /// Creates a directory inside `directory`, returning its URL.
    ///
    /// - Parameters:
    ///   - name: Folder name, as typed by the user.
    ///   - directory: Parent directory.
    /// - Returns: The created folder's URL.
    /// - Throws: ``FileExplorerFileOperationError/alreadyExists`` if the name is taken, or
    ///   any error `FileManager` raises.
    static func createDirectory(named name: String, in directory: URL) throws -> URL {
        let url = directory.appendingPathComponent(name)
        guard !FileManager.default.fileExists(atPath: url.path) else {
            throw FileExplorerFileOperationError.alreadyExists(name)
        }
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        return url
    }

    /// Renames the item at `url`.
    ///
    /// - Parameters:
    ///   - url: Item to rename.
    ///   - newName: New name, without a path.
    /// - Returns: The item's new URL.
    /// - Throws: ``FileExplorerFileOperationError/alreadyExists`` if the name is taken, or
    ///   any error `FileManager` raises.
    static func rename(_ url: URL, to newName: String) throws -> URL {
        let destination = url.deletingLastPathComponent().appendingPathComponent(newName)
        guard destination != url else { return url }
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            throw FileExplorerFileOperationError.alreadyExists(newName)
        }
        try FileManager.default.moveItem(at: url, to: destination)
        return destination
    }

    /// Copies the item at `url` beside itself, suffixing the name until it is free.
    ///
    /// The suffix goes before the extension (`notes copy.txt`, not `notes.txt copy`) so the
    /// duplicate keeps opening in the same application as the original.
    ///
    /// - Parameter url: Item to duplicate.
    /// - Returns: The duplicate's URL.
    /// - Throws: Any error `FileManager` raises.
    static func duplicate(_ url: URL) throws -> URL {
        let directory = url.deletingLastPathComponent()
        let ext = url.pathExtension
        let base = url.deletingPathExtension().lastPathComponent

        var candidate = directory.appendingPathComponent("\(base) copy")
        if !ext.isEmpty { candidate.appendPathExtension(ext) }

        var counter = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(base) copy \(counter)")
            if !ext.isEmpty { candidate.appendPathExtension(ext) }
            counter += 1
        }

        try FileManager.default.copyItem(at: url, to: candidate)
        return candidate
    }

    /// Copies `source` into `directory`, uniquifying the destination name when it collides.
    ///
    /// Uniquification matches the Finder: `foo.txt` next to an existing `foo.txt` becomes
    /// `foo 2.txt`, `foo 3.txt`, and so on. Called from the Files tree's drop handler; the
    /// alternative — throwing on collision — would surface as "the drag did nothing" for
    /// the common case of dropping a downloaded file into a folder that already has one.
    ///
    /// - Parameters:
    ///   - source: File or directory to copy.
    ///   - directory: Destination folder. Must exist.
    /// - Returns: The URL of the freshly written copy.
    /// - Throws: Any error `FileManager` raises.
    @discardableResult
    static func copyInto(_ source: URL, directory: URL) throws -> URL {
        let destination = uniquifiedDestination(named: source.lastPathComponent, in: directory)
        try FileManager.default.copyItem(at: source, to: destination)
        return destination
    }

    /// Moves `source` into `directory`, uniquifying the destination name when it collides.
    ///
    /// Same uniquification rule as ``copyInto(_:directory:)``. A drop of a file from
    /// somewhere else on the same volume is a rename under the hood; the OS handles it
    /// atomically.
    ///
    /// - Parameters:
    ///   - source: File or directory to move.
    ///   - directory: Destination folder. Must exist.
    /// - Returns: The URL of the moved item.
    /// - Throws: Any error `FileManager` raises.
    @discardableResult
    static func moveInto(_ source: URL, directory: URL) throws -> URL {
        let destination = uniquifiedDestination(named: source.lastPathComponent, in: directory)
        try FileManager.default.moveItem(at: source, to: destination)
        return destination
    }

    /// Finds a destination name that does not collide.
    ///
    /// Same pattern as ``duplicate(_:)`` — a `foo.txt` becomes `foo 2.txt`, then
    /// `foo 3.txt`, etc. Kept internal to the operation surface so the numbering rule stays
    /// in one place.
    private static func uniquifiedDestination(named name: String, in directory: URL) -> URL {
        let candidate = directory.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: candidate.path) else { return candidate }
        let ns = name as NSString
        let stem = ns.deletingPathExtension
        let ext = ns.pathExtension
        var index = 2
        while true {
            let suffix = ext.isEmpty ? "\(stem) \(index)" : "\(stem) \(index).\(ext)"
            let attempt = directory.appendingPathComponent(suffix)
            if !FileManager.default.fileExists(atPath: attempt.path) { return attempt }
            index += 1
        }
    }

    /// Moves the item at `url` to the Trash.
    ///
    /// - Parameter url: Item to trash.
    /// - Returns: Where the item landed in the Trash, when the system reports it. Callers in
    ///   the app ignore this; it exists so a test can clean up after itself instead of
    ///   leaving debris in the user's Trash on every run.
    /// - Throws: Any error `FileManager` raises.
    @discardableResult
    static func moveToTrash(_ url: URL) throws -> URL? {
        var resulting: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &resulting)
        return resulting as URL?
    }
}

/// Why a file-tree write could not be performed.
enum FileExplorerFileOperationError: LocalizedError {
    /// Something already exists at the requested name.
    case alreadyExists(String)
    /// `FileManager` refused to create the file without saying why.
    case createFailed(String)

    var errorDescription: String? {
        switch self {
        case let .alreadyExists(name):
            return String(
                localized: "fileExplorer.error.alreadyExists",
                defaultValue: "“\(name)” already exists."
            )
        case let .createFailed(name):
            return String(
                localized: "fileExplorer.error.createFailed",
                defaultValue: "Could not create “\(name)”."
            )
        }
    }
}

/// A single-field prompt for a file or folder name.
///
/// A sheet rather than a free-floating alert so it stays attached to the window whose tree
/// was clicked, and returns `nil` when the user cancels or types only whitespace.
@MainActor
enum FileExplorerNamePrompt {
    /// Asks for a name.
    ///
    /// - Parameters:
    ///   - title: Sheet title.
    ///   - initialValue: Pre-filled text, selected so typing replaces it.
    ///   - window: Window to attach the sheet to. A modal alert is used when `nil`.
    /// - Returns: The trimmed name, or `nil` if cancelled or blank.
    static func run(title: String, initialValue: String, window: NSWindow?) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.addButton(withTitle: String(localized: "common.ok", defaultValue: "OK"))
        alert.addButton(withTitle: String(localized: "common.cancel", defaultValue: "Cancel"))

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.stringValue = initialValue
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return nil }
        let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }

    /// Reports a failed operation.
    ///
    /// - Parameters:
    ///   - error: What went wrong.
    ///   - window: Window to attach the sheet to.
    static func presentFailure(_ error: Error, window: NSWindow?) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = error.localizedDescription
        alert.addButton(withTitle: String(localized: "common.ok", defaultValue: "OK"))
        alert.runModal()
    }
}
