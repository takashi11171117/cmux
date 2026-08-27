import Foundation

/// One line of the Git sidebar's tree, already flattened for a linear `ForEach`.
///
/// The sidebar draws a flat `LazyVStack` rather than an `OutlineGroup`. Flattening keeps the
/// collapse state a plain `Set` of folder paths owned above the `ForEach` boundary, instead of
/// per-row observable state below it — which is the shape that reintroduces the spin loop from
/// upstream #2586.
///
/// ```swift
/// let rows = GitChangeTreeRow.rows(entries: entries, root: root, collapsedFolders: [])
/// ```
struct GitChangeTreeRow: Identifiable, Equatable, Sendable {
    /// What a row draws.
    enum Kind: Equatable, Sendable {
        /// A directory, with the number of changed files anywhere beneath it.
        case folder(isCollapsed: Bool, changeCount: Int)
        /// A changed file.
        case file(GitChangeEntry)
    }

    /// Folder rows are identified by their path relative to the root, file rows by their
    /// absolute path. The two cannot collide: a relative path never starts with `/`.
    let id: String
    /// Text the row shows. A directory that holds nothing but one more directory is joined
    /// with its child, so `docs/fork` is one row rather than two nearly empty ones.
    let name: String
    /// How many levels to indent.
    let depth: Int
    let kind: Kind

    /// Flattens the changed files into rows, deepest-first within each directory.
    ///
    /// Directories come before files at every level, and both are ordered case-insensitively,
    /// so the order the eye reads matches the order the rows are in. The flat path-sorted list
    /// this replaced was sorted correctly but *looked* unsorted, because the file name — the
    /// first thing read — was not what it was sorted by.
    ///
    /// - Parameters:
    ///   - entries: Changed files, in any order.
    ///   - root: Directory the list is rooted at.
    ///   - collapsedFolders: Folder ids whose contents are hidden. Ids that no longer match a
    ///     folder are ignored, so a stale entry left by a deleted directory is harmless.
    /// - Returns: Rows in display order.
    static func rows(
        entries: [GitChangeEntry],
        root: String,
        collapsedFolders: Set<String>
    ) -> [GitChangeTreeRow] {
        let tree = Node()
        for entry in entries {
            let components = (entry.relativeDirectory(from: root) ?? "")
                .split(separator: "/")
                .map(String.init)
            var node = tree
            for component in components {
                node = node.child(named: component)
            }
            node.files.append(entry)
        }
        var rows: [GitChangeTreeRow] = []
        tree.appendRows(prefix: "", depth: 0, collapsedFolders: collapsedFolders, into: &rows)
        return rows
    }

    /// Build-time only: a directory in the tree being assembled.
    ///
    /// A reference type because assembly walks down and mutates in place; it never escapes
    /// ``rows(entries:root:collapsedFolders:)``.
    private final class Node {
        var directories: [String: Node] = [:]
        var files: [GitChangeEntry] = []

        func child(named name: String) -> Node {
            if let existing = directories[name] { return existing }
            let created = Node()
            directories[name] = created
            return created
        }

        /// Changed files in this directory and everything below it.
        var totalFileCount: Int {
            files.count + directories.values.reduce(0) { $0 + $1.totalFileCount }
        }

        func appendRows(
            prefix: String,
            depth: Int,
            collapsedFolders: Set<String>,
            into rows: inout [GitChangeTreeRow]
        ) {
            for name in directories.keys.sorted(by: Node.precedes) {
                guard let child = directories[name] else { continue }
                // Collapse a chain of directories that each hold nothing but the next one.
                // In a deep source tree those rows carry no information and cost the indent
                // the file names need.
                var displayName = name
                var path = prefix.isEmpty ? name : prefix + "/" + name
                var node = child
                while node.files.isEmpty,
                      node.directories.count == 1,
                      let onlyChild = node.directories.first {
                    displayName += "/" + onlyChild.key
                    path += "/" + onlyChild.key
                    node = onlyChild.value
                }
                let isCollapsed = collapsedFolders.contains(path)
                rows.append(GitChangeTreeRow(
                    id: path,
                    name: displayName,
                    depth: depth,
                    kind: .folder(isCollapsed: isCollapsed, changeCount: node.totalFileCount)
                ))
                guard !isCollapsed else { continue }
                node.appendRows(
                    prefix: path,
                    depth: depth + 1,
                    collapsedFolders: collapsedFolders,
                    into: &rows
                )
            }
            for entry in files.sorted(by: { Node.precedes($0.fileName, $1.fileName) }) {
                rows.append(GitChangeTreeRow(
                    id: entry.path,
                    name: entry.fileName,
                    depth: depth,
                    kind: .file(entry)
                ))
            }
        }

        /// Case-insensitive ordering, falling back to the raw value so it is a strict ordering
        /// even when two names differ only in case. Deliberately not locale-aware: the order
        /// rows appear in should not change with the user's region.
        static func precedes(_ lhs: String, _ rhs: String) -> Bool {
            let left = lhs.lowercased()
            let right = rhs.lowercased()
            return left == right ? lhs < rhs : left < right
        }
    }
}
