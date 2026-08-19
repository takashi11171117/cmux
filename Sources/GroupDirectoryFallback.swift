import Foundation

/// Directory a directory-less workspace borrows from its group.
///
/// A Claude/agent session workspace often reports no working directory of its own, which
/// left the Files and Git tabs empty while sitting right next to the group's terminal that
/// is parked in the repository. Group members review one checkout; a member that cannot
/// name it borrows it.
///
/// Pure values in, pure value out — the caller flattens `TabManager` state into `Member`s so
/// this stays testable without constructing workspaces.
enum GroupDirectoryFallback {
    /// One group member, as much of it as resolution needs.
    struct Member {
        /// The member workspace's id.
        let id: UUID
        /// Its current directory, raw; blank and whitespace-only values count as absent.
        let directory: String?

        /// The usable directory, or `nil`.
        var normalizedDirectory: String? {
            guard let directory else { return nil }
            let trimmed = directory.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
    }

    /// Picks the directory to borrow.
    ///
    /// The group's anchor wins when it has one — it is the member that owns the group's
    /// lifecycle, which in practice is the terminal the group was formed around. Otherwise
    /// the first member in tabs order with a directory is used, so the answer is stable
    /// across calls rather than dependent on dictionary order.
    ///
    /// - Parameters:
    ///   - anchorWorkspaceId: The group's anchor, when known.
    ///   - members: Group members in tabs order. Include only members whose directory is a
    ///     local path; remote-provenance workspaces do not belong here.
    ///   - selfId: The workspace asking to borrow; never borrows from itself.
    /// - Returns: The lender and its directory, or `nil` when no member can lend one.
    static func resolve(
        anchorWorkspaceId: UUID?,
        members: [Member],
        excluding selfId: UUID
    ) -> (workspaceId: UUID, path: String)? {
        if let anchorWorkspaceId,
           anchorWorkspaceId != selfId,
           let anchor = members.first(where: { $0.id == anchorWorkspaceId }),
           let path = anchor.normalizedDirectory {
            return (anchor.id, path)
        }
        for member in members where member.id != selfId {
            if let path = member.normalizedDirectory {
                return (member.id, path)
            }
        }
        return nil
    }
}
