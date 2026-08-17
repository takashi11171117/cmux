import AppKit
import Foundation
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

@Suite("FilePreviewExternalOpenLocation")
struct FilePreviewExternalOpenLocationTests {
    @Test("offset zero is line one")
    func offsetZeroIsLineOne() {
        #expect(FilePreviewExternalOpenLocation.lineNumber(in: "" as NSString, atUTF16Offset: 0) == 1)
        #expect(FilePreviewExternalOpenLocation.lineNumber(in: "abc" as NSString, atUTF16Offset: 0) == 1)
    }

    @Test("the line advances past each newline")
    func newlinesAdvanceTheLine() {
        let text = "a\nbb\nccc" as NSString
        #expect(FilePreviewExternalOpenLocation.lineNumber(in: text, atUTF16Offset: 0) == 1)
        #expect(FilePreviewExternalOpenLocation.lineNumber(in: text, atUTF16Offset: 1) == 1)
        #expect(FilePreviewExternalOpenLocation.lineNumber(in: text, atUTF16Offset: 2) == 2)
        #expect(FilePreviewExternalOpenLocation.lineNumber(in: text, atUTF16Offset: 5) == 3)
        #expect(FilePreviewExternalOpenLocation.lineNumber(in: text, atUTF16Offset: 8) == 3)
    }

    @Test("offsets past the end clamp to the last line")
    func offsetPastEndClamps() {
        #expect(FilePreviewExternalOpenLocation.lineNumber(in: "a\nb" as NSString, atUTF16Offset: 9_999) == 2)
    }

    @Test("negative offsets clamp to line one")
    func negativeOffsetClamps() {
        #expect(FilePreviewExternalOpenLocation.lineNumber(in: "a\nb" as NSString, atUTF16Offset: -5) == 1)
    }

    @Test("surrogate pairs do not shift the line")
    func surrogatePairs() {
        // "😀" is two UTF-16 units, so the newline sits at offset 2 and line 2 starts at 3.
        let text = "😀\nx" as NSString
        #expect(FilePreviewExternalOpenLocation.lineNumber(in: text, atUTF16Offset: 1) == 1)
        #expect(FilePreviewExternalOpenLocation.lineNumber(in: text, atUTF16Offset: 3) == 2)
    }

    @Test("CRLF counts as one break")
    func crlf() {
        let text = "a\r\nb" as NSString
        #expect(FilePreviewExternalOpenLocation.lineNumber(in: text, atUTF16Offset: 1) == 1)
        #expect(FilePreviewExternalOpenLocation.lineNumber(in: text, atUTF16Offset: 3) == 2)
    }

    @MainActor
    @Test("the caret initializer reads the text view's selection")
    func caretInitializerReadsSelection() {
        let textView = SavingTextView.makeFilePreviewTextView()
        textView.string = "one\ntwo\nthree"
        textView.setSelectedRange(NSRange(location: 8, length: 0))

        let location = FilePreviewExternalOpenLocation(
            fileURL: URL(fileURLWithPath: "/tmp/a.swift"), caretIn: textView
        )
        #expect(location.line == 3)
        #expect(location.fileURL.path == "/tmp/a.swift")
    }

    @MainActor
    @Test("the caret line does not depend on the line-number index")
    func caretIsIndependentOfLineNumberSetting() {
        // FilePreviewLineIndex is only built when the ruler is enabled. Opening externally
        // must not lose the line just because someone turned line numbers off.
        let textView = SavingTextView.makeFilePreviewTextView()
        textView.string = "alpha\nbeta\ngamma"
        textView.setSelectedRange(NSRange(location: 12, length: 0))

        let viaCaret = FilePreviewExternalOpenLocation(
            fileURL: URL(fileURLWithPath: "/tmp/a.swift"), caretIn: textView
        ).line
        let viaIndex = FilePreviewLineIndex(text: textView.string as NSString, generation: 0)
            .lineNumber(atUTF16Offset: 12)
        #expect(viaCaret == viaIndex)
    }
}
