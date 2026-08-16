import AppKit
import Foundation
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

@MainActor
@Suite("FilePreviewLineNumberRulerView", .serialized)
struct FilePreviewLineNumberRulerViewTests {
    private struct Harness {
        let textView: SavingTextView
        let scrollView: NSScrollView
        let ruler: FilePreviewLineNumberRulerView
    }

    private func makeHarness(text: String) -> Harness {
        let textView = SavingTextView.makeFilePreviewTextView()
        textView.string = text
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        scrollView.documentView = textView
        let ruler = FilePreviewLineNumberRulerView(scrollView: scrollView, textView: textView)
        scrollView.hasVerticalRuler = true
        scrollView.verticalRulerView = ruler
        scrollView.rulersVisible = true
        scrollView.layoutSubtreeIfNeeded()
        return Harness(textView: textView, scrollView: scrollView, ruler: ruler)
    }

    @Test("the ruler counts logical lines from the initial document")
    func initialLineCount() {
        let harness = makeHarness(text: "a\nbb\nccc")
        #expect(harness.ruler.numberedLineCount == 3)
    }

    @Test("typing without a newline keeps the line count")
    func typingKeepsCount() {
        let harness = makeHarness(text: "a\nbb\n")
        let before = harness.ruler.numberedLineCount
        harness.textView.textStorage?.replaceCharacters(in: NSRange(location: 1, length: 0), with: "X")
        #expect(harness.ruler.numberedLineCount == before)
    }

    @Test("inserting a newline through the storage updates the ruler")
    func newlineInsertionUpdatesRuler() {
        // Proves the ruler is wired as the storage's delegate: nothing else would tell it
        // that the document gained a line.
        let harness = makeHarness(text: "abc")
        #expect(harness.ruler.numberedLineCount == 1)
        harness.textView.textStorage?.replaceCharacters(in: NSRange(location: 1, length: 0), with: "\n")
        #expect(harness.ruler.numberedLineCount == 2)
    }

    @Test("deleting a newline through the storage updates the ruler")
    func newlineDeletionUpdatesRuler() {
        let harness = makeHarness(text: "a\nb")
        #expect(harness.ruler.numberedLineCount == 2)
        harness.textView.textStorage?.replaceCharacters(in: NSRange(location: 1, length: 1), with: "")
        #expect(harness.ruler.numberedLineCount == 1)
    }

    @Test("a wholesale replacement rebuilds the index")
    func resetIndexRebuilds() {
        let harness = makeHarness(text: "a\nb")
        harness.ruler.resetIndex(text: "1\n2\n3\n4" as NSString)
        #expect(harness.ruler.numberedLineCount == 4)
    }

    @Test("only logical line starts are numbered")
    func onlyLogicalStartsAreNumbered() {
        let harness = makeHarness(text: "alpha\nbeta")
        #expect(harness.ruler.startsLogicalLine(atUTF16Offset: 0))
        #expect(harness.ruler.startsLogicalLine(atUTF16Offset: 6))
        // Offsets inside a line — where a soft wrap would place a continuation fragment.
        #expect(!harness.ruler.startsLogicalLine(atUTF16Offset: 3))
        #expect(!harness.ruler.startsLogicalLine(atUTF16Offset: 8))
    }

    @Test("the gutter widens as the line count gains digits")
    func gutterWidensWithDigits() {
        let narrow = makeHarness(text: "a\nb\nc")
        let narrowThickness = narrow.ruler.ruleThickness

        let wide = makeHarness(text: String(repeating: "line\n", count: 12_000))
        let wideThickness = wide.ruler.ruleThickness

        #expect(narrowThickness > 0)
        #expect(wideThickness > narrowThickness, "a 5-digit file should reserve more gutter than a 1-digit file")
    }

    @Test("a short file still reserves a minimum gutter")
    func minimumGutter() {
        // Otherwise the text would visibly shift right the moment a file crosses 10 lines.
        let single = makeHarness(text: "only one line")
        let ten = makeHarness(text: String(repeating: "x\n", count: 9))
        #expect(single.ruler.ruleThickness == ten.ruler.ruleThickness)
    }

    @Test("changing the font re-measures the gutter")
    func fontChangeRemeasures() {
        let harness = makeHarness(text: "a\nb\nc")
        let before = harness.ruler.ruleThickness
        harness.ruler.adoptFont(NSFont.monospacedSystemFont(ofSize: 32, weight: .regular))
        #expect(harness.ruler.ruleThickness > before)
    }
}
