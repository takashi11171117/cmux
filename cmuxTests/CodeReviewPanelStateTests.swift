import Foundation
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

/// Covers the code-review column's width clamping.
///
/// Only the pure sizing rule is exercised here. The rest of ``CodeReviewPanelState`` drives a
/// real ``Workspace``, which needs the Ghostty runtime and an app host, so it is verified by
/// the manual test plan rather than pretended to be unit-testable.
@Suite("CodeReviewPanelState")
struct CodeReviewPanelStateTests {
    private let minimum = CodeReviewPanelState.minimumWidth
    private let maximum = CodeReviewPanelState.maximumWidth

    @Test("a comfortable request in a wide window is returned unchanged")
    func passesThroughUsableWidth() {
        let width = CodeReviewPanelState.clampedWidth(600, availableWidth: 2_000)
        #expect(width == 600)
    }

    @Test("a request below the minimum is raised to it")
    func raisesBelowMinimum() {
        let width = CodeReviewPanelState.clampedWidth(10, availableWidth: 2_000)
        #expect(width == minimum)
    }

    @Test("a request above the maximum is capped")
    func capsAboveMaximum() {
        let width = CodeReviewPanelState.clampedWidth(9_999, availableWidth: 10_000)
        #expect(width == maximum)
    }

    @Test("the column may not take more than 60% of the window")
    func leavesRoomForTheTerminal() {
        // The column exists so the terminal stays visible; letting it grow without bound
        // would defeat that.
        let width = CodeReviewPanelState.clampedWidth(9_999, availableWidth: 1_000)
        #expect(width == 600)
    }

    @Test("in a narrow window the minimum wins over the 60% rule")
    func minimumBeatsPercentageWhenWindowIsNarrow() {
        // 60% of 400 is 240, below the 320 minimum. Returning 240 would render a column too
        // narrow to read code in.
        let width = CodeReviewPanelState.clampedWidth(500, availableWidth: 400)
        #expect(width == minimum)
    }

    @Test("clamping is idempotent")
    func clampingIsIdempotent() {
        for requested in [CGFloat(10), 320, 600, 1_400, 9_999] {
            let once = CodeReviewPanelState.clampedWidth(requested, availableWidth: 2_000)
            let twice = CodeReviewPanelState.clampedWidth(once, availableWidth: 2_000)
            #expect(once == twice, "requested \(requested)")
        }
    }

    @Test("a zero-width window still yields the minimum rather than zero")
    func degenerateWindowYieldsMinimum() {
        // Reached during window setup, before a real size is known. A zero-width column
        // would be invisible with no way to drag it back.
        let width = CodeReviewPanelState.clampedWidth(CodeReviewPanelState.defaultWidth, availableWidth: 0)
        #expect(width == minimum)
    }

    @Test("the default width is itself within the allowed range")
    func defaultWidthIsValid() {
        #expect(CodeReviewPanelState.defaultWidth >= minimum)
        #expect(CodeReviewPanelState.defaultWidth <= maximum)
    }
}
