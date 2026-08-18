import Foundation

/// One changed file, as the Git sidebar shows it.
///
/// A value type rather than a view model: rows sit under a `ForEach`, and anything holding an
/// observable store below that boundary reintroduces the spin loop this codebase already
/// fixed once (upstream #2586). Rows get values and callbacks, never the store.
struct GitChangeEntry: Identifiable, Equatable, Sendable {
    /// Absolute path, as `FileExplorerStore` spells it.
    let path: String
    /// Working-tree status for the file.
    let status: GitFileStatus

    var id: String { path }

    /// Last path component, shown as the row's title.
    var fileName: String { (path as NSString).lastPathComponent }

    /// Path relative to `root`, without the file name — shown dimmed beside the title.
    ///
    /// - Parameter root: Directory the list is rooted at.
    /// - Returns: The relative directory, or `nil` when the file sits directly in `root`.
    func relativeDirectory(from root: String) -> String? {
        let directory = (path as NSString).deletingLastPathComponent
        guard !directory.isEmpty, directory != root else { return nil }
        guard directory.hasPrefix(root) else { return directory }
        let trimmed = String(directory.dropFirst(root.count))
        let cleaned = trimmed.hasPrefix("/") ? String(trimmed.dropFirst()) : trimmed
        return cleaned.isEmpty ? nil : cleaned
    }

    /// Single-letter badge, matching what `git status --short` prints.
    var badge: String {
        switch status {
        case .modified: return "M"
        case .added: return "A"
        case .deleted: return "D"
        case .renamed: return "R"
        case .untracked: return "?"
        }
    }

    /// Builds the sorted list the sidebar renders.
    ///
    /// Sorted by path so the order is stable between refreshes; `git status` returns a
    /// dictionary, and rendering it unsorted would reshuffle rows on every keystroke that
    /// touches a file.
    ///
    /// - Parameter statusByPath: The store's `gitStatusByPath` snapshot.
    /// - Returns: Entries in path order.
    static func entries(from statusByPath: [String: GitFileStatus]) -> [GitChangeEntry] {
        statusByPath
            .map { GitChangeEntry(path: $0.key, status: $0.value) }
            .sorted { $0.path < $1.path }
    }
}
