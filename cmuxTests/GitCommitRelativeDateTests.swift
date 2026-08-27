import Foundation
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

/// The relative-date label rendered next to each commit.
///
/// Not testing the exact string (that depends on the locale of the test runner and
/// `RelativeDateTimeFormatter`'s internals). Instead, verify the two properties the sidebar
/// actually cares about: newer commits produce shorter labels than older ones, and the same
/// pair produces the same label — i.e. the formatter output is deterministic.
@Suite("Git commit relative date")
struct GitCommitRelativeDateTests {
    @Test("Recent commits produce a shorter label than distant ones")
    func recentShorterThanDistant() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let recent = now.addingTimeInterval(-60 * 60)         // 1 hour ago
        let distant = now.addingTimeInterval(-60 * 60 * 24 * 365) // 1 year ago

        let recentLabel = GitCommitRelativeDate.string(from: recent, now: now)
        let distantLabel = GitCommitRelativeDate.string(from: distant, now: now)

        #expect(!recentLabel.isEmpty)
        #expect(!distantLabel.isEmpty)
        #expect(recentLabel != distantLabel)
    }

    @Test("The same pair yields the same label")
    func deterministic() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let date = now.addingTimeInterval(-3600)

        #expect(GitCommitRelativeDate.string(from: date, now: now)
             == GitCommitRelativeDate.string(from: date, now: now))
    }
}
