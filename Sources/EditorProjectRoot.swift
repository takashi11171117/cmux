import Foundation

/// The directory an editor should be handed as "the project" a file belongs to.
///
/// A file on its own gives an editor no context: no sibling files, no search, no jump-to-symbol.
/// Handing it the enclosing project instead is the difference between a lone tab and a usable
/// workspace.
///
/// ```swift
/// let root = EditorProjectRoot(
///     filePath: "/repo/app/Sources/App.swift",
///     candidates: ["/repo", "/repo/app"]
/// )
/// // root?.path == "/repo/app"
/// ```
struct EditorProjectRoot: Equatable, Sendable {
    /// Absolute path of the directory to open.
    let path: String

    /// Picks the project directory for a file.
    ///
    /// The deepest candidate wins, because the more specific directory is the one the user is
    /// actually working in. Both directions of the mismatch happen: a workspace rooted inside a
    /// monorepo should not drag in the whole repository, and a workspace rooted at a folder of
    /// several repositories should open the one repository the file lives in — not the folder
    /// holding all of them.
    ///
    /// - Parameters:
    ///   - filePath: Absolute path of the file being opened.
    ///   - candidates: Directories that could be the project — typically the file's git
    ///     repository root and the directory the file explorer is rooted at, in any order.
    ///     Empty or non-containing entries are ignored.
    /// - Returns: `nil` when no candidate contains the file, in which case the file should be
    ///   opened on its own rather than alongside a directory it does not belong to.
    init?(filePath: String, candidates: [String]) {
        let fileComponents = Self.components(of: filePath)
        guard !fileComponents.isEmpty else { return nil }

        var best: [String]?
        for candidate in candidates {
            let candidateComponents = Self.components(of: candidate)
            guard !candidateComponents.isEmpty else { continue }
            // Compared component by component, never as a string prefix: `/a/bc` is not inside
            // `/a/b`, but its path certainly starts with it.
            guard candidateComponents.count < fileComponents.count,
                  Array(fileComponents.prefix(candidateComponents.count)) == candidateComponents
            else { continue }
            if candidateComponents.count > (best?.count ?? 0) {
                best = candidateComponents
            }
        }

        guard let best else { return nil }
        path = "/" + best.joined(separator: "/")
    }

    /// Path components with symlinks resolved, so two spellings of the same directory compare
    /// equal. Returns an empty array for a path that is empty or the filesystem root.
    private static func components(of path: String) -> [String] {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        return URL(fileURLWithPath: trimmed)
            .standardizedFileURL
            .resolvingSymlinksInPath()
            .pathComponents
            .filter { $0 != "/" }
    }
}
