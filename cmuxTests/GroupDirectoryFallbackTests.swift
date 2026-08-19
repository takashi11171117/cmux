import Foundation
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

/// Covers which group member lends its directory to a directory-less workspace.
///
/// The behavior exists so a Claude session workspace shows the group terminal's Git state
/// instead of an empty tab; these pin the lending order so it stays predictable.
@Suite("GroupDirectoryFallback")
struct GroupDirectoryFallbackTests {
    private let selfId = UUID()
    private let anchorId = UUID()
    private let otherId = UUID()

    private func member(_ id: UUID, _ dir: String?) -> GroupDirectoryFallback.Member {
        GroupDirectoryFallback.Member(id: id, directory: dir)
    }

    @Test("the anchor lends first")
    func anchorWins() {
        let result = GroupDirectoryFallback.resolve(
            anchorWorkspaceId: anchorId,
            members: [
                member(otherId, "/repo/other"),
                member(anchorId, "/repo/anchor"),
            ],
            excluding: selfId
        )
        #expect(result?.workspaceId == anchorId)
        #expect(result?.path == "/repo/anchor")
    }

    @Test("an anchor without a directory falls through to tabs order")
    func anchorWithoutDirectoryFallsThrough() {
        let result = GroupDirectoryFallback.resolve(
            anchorWorkspaceId: anchorId,
            members: [
                member(anchorId, "   "),
                member(otherId, "/repo/other"),
            ],
            excluding: selfId
        )
        #expect(result?.workspaceId == otherId)
    }

    @Test("never borrows from itself, even as anchor")
    func neverSelf() {
        let result = GroupDirectoryFallback.resolve(
            anchorWorkspaceId: selfId,
            members: [
                member(selfId, "/repo/self"),
                member(otherId, "/repo/other"),
            ],
            excluding: selfId
        )
        #expect(result?.workspaceId == otherId)
    }

    @Test("tabs order decides when there is no anchor")
    func tabsOrderWithoutAnchor() {
        let first = UUID()
        let result = GroupDirectoryFallback.resolve(
            anchorWorkspaceId: nil,
            members: [
                member(selfId, nil),
                member(first, "/repo/first"),
                member(otherId, "/repo/second"),
            ],
            excluding: selfId
        )
        #expect(result?.workspaceId == first)
    }

    @Test("whitespace-only directories count as absent")
    func whitespaceIsAbsent() {
        let result = GroupDirectoryFallback.resolve(
            anchorWorkspaceId: nil,
            members: [member(otherId, "  \n ")],
            excluding: selfId
        )
        #expect(result == nil)
    }

    @Test("no lendable member yields nil")
    func emptyGroup() {
        #expect(GroupDirectoryFallback.resolve(
            anchorWorkspaceId: nil, members: [], excluding: selfId
        ) == nil)
        #expect(GroupDirectoryFallback.resolve(
            anchorWorkspaceId: anchorId,
            members: [member(selfId, "/repo/self")],
            excluding: selfId
        ) == nil)
    }

    @Test("the lent path is trimmed")
    func pathIsTrimmed() {
        let result = GroupDirectoryFallback.resolve(
            anchorWorkspaceId: nil,
            members: [member(otherId, "  /repo/other \n")],
            excluding: selfId
        )
        #expect(result?.path == "/repo/other")
    }
}
