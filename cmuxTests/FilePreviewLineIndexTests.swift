import Foundation
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

@Suite("FilePreviewLineIndex")
struct FilePreviewLineIndexTests {
    /// Deterministic generator so a failing edit sequence can be replayed.
    private struct SeededRandom: RandomNumberGenerator {
        private var state: UInt64

        init(seed: UInt64) { state = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed }

        mutating func next() -> UInt64 {
            state ^= state << 13
            state ^= state >> 7
            state ^= state << 17
            return state
        }
    }

    /// Compares every observable answer against a freshly built index.
    private func expectMatchesRebuild(
        _ index: FilePreviewLineIndex,
        text: NSString,
        _ context: @autoclosure () -> String = "",
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        let rebuilt = FilePreviewLineIndex(text: text, generation: index.generation)
        #expect(
            index.lineCount == rebuilt.lineCount,
            "lineCount \(index.lineCount) != \(rebuilt.lineCount) \(context())",
            sourceLocation: sourceLocation
        )
        for offset in 0...text.length {
            #expect(
                index.lineNumber(atUTF16Offset: offset) == rebuilt.lineNumber(atUTF16Offset: offset),
                "lineNumber at \(offset) diverged \(context())",
                sourceLocation: sourceLocation
            )
            #expect(
                index.isLineStart(utf16Offset: offset) == rebuilt.isLineStart(utf16Offset: offset),
                "isLineStart at \(offset) diverged \(context())",
                sourceLocation: sourceLocation
            )
        }
    }

    @Test("empty text is one line")
    func emptyText() {
        let index = FilePreviewLineIndex(text: "" as NSString, generation: 1)
        #expect(index.lineCount == 1)
        #expect(index.lineNumber(atUTF16Offset: 0) == 1)
        #expect(index.isLineStart(utf16Offset: 0))
    }

    @Test("text without a trailing newline")
    func noTrailingNewline() {
        let index = FilePreviewLineIndex(text: "a\nbb\nccc" as NSString, generation: 1)
        #expect(index.lineCount == 3)
        #expect(index.lineNumber(atUTF16Offset: 0) == 1)
        #expect(index.lineNumber(atUTF16Offset: 1) == 1)
        #expect(index.lineNumber(atUTF16Offset: 2) == 2)
        #expect(index.lineNumber(atUTF16Offset: 4) == 2)
        #expect(index.lineNumber(atUTF16Offset: 5) == 3)
        #expect(index.lineNumber(atUTF16Offset: 8) == 3)
        #expect(index.isLineStart(utf16Offset: 2))
        #expect(index.isLineStart(utf16Offset: 5))
        #expect(!index.isLineStart(utf16Offset: 3))
    }

    @Test("a trailing newline opens a final empty line")
    func trailingNewline() {
        let index = FilePreviewLineIndex(text: "a\nbb\n" as NSString, generation: 1)
        #expect(index.lineCount == 3)
        #expect(index.lineNumber(atUTF16Offset: 5) == 3)
        #expect(index.isLineStart(utf16Offset: 5))
    }

    @Test("consecutive newlines make empty lines")
    func consecutiveNewlines() {
        let index = FilePreviewLineIndex(text: "\n\n\n" as NSString, generation: 1)
        #expect(index.lineCount == 4)
        for offset in 0...3 {
            #expect(index.isLineStart(utf16Offset: offset), "offset \(offset) should start a line")
        }
    }

    @Test("CRLF counts as one break, keeping the CR on the line it ends")
    func crlf() {
        let index = FilePreviewLineIndex(text: "a\r\nb" as NSString, generation: 1)
        #expect(index.lineCount == 2)
        #expect(index.lineNumber(atUTF16Offset: 1) == 1)  // the CR
        #expect(index.lineNumber(atUTF16Offset: 3) == 2)  // "b"
        #expect(index.isLineStart(utf16Offset: 3))
        #expect(!index.isLineStart(utf16Offset: 2))
    }

    @Test("surrogate pairs advance offsets by two")
    func surrogatePairs() {
        // "😀" is one Character but two UTF-16 code units, so the newline after it sits
        // at offset 2 and the next line starts at 3.
        let text = "😀\nx" as NSString
        #expect(text.length == 4)
        let index = FilePreviewLineIndex(text: text, generation: 1)
        #expect(index.lineCount == 2)
        #expect(index.lineNumber(atUTF16Offset: 1) == 1)
        #expect(index.lineNumber(atUTF16Offset: 3) == 2)
        #expect(index.isLineStart(utf16Offset: 3))
    }

    @Test("offsets past the end clamp to the last line")
    func offsetPastEnd() {
        let index = FilePreviewLineIndex(text: "a\nb" as NSString, generation: 1)
        #expect(index.lineNumber(atUTF16Offset: 999) == 2)
    }

    @Test("generation survives patching")
    func generationSurvivesPatch() {
        // A stale index must stay identifiable after edits, otherwise the controller
        // cannot tell that an index built off the main actor describes older text.
        let index = FilePreviewLineIndex(text: "abc" as NSString, generation: 42)
        let patched = index.patched(
            editedRange: NSRange(location: 1, length: 0), changeInLength: 1, text: "aXbc" as NSString
        )
        #expect(patched.generation == 42)
    }

    @Test("insertion without a newline takes the fast path and stays correct")
    func insertWithoutNewline() {
        let index = FilePreviewLineIndex(text: "ab\ncd" as NSString, generation: 1)
        let text = "aXXb\ncd" as NSString
        let patched = index.patched(
            editedRange: NSRange(location: 1, length: 0), changeInLength: 2, text: text
        )
        expectMatchesRebuild(patched, text: text, "insert without newline")
    }

    @Test("deleting only the newline removes a line")
    func deleteOnlyNewline() {
        // The regression that motivated the inclusive upper bound: the removed line
        // start sits exactly at the end of the edited range.
        let index = FilePreviewLineIndex(text: "ab\ncd" as NSString, generation: 1)
        let text = "abcd" as NSString
        let patched = index.patched(
            editedRange: NSRange(location: 2, length: 1), changeInLength: -1, text: text
        )
        #expect(patched.lineCount == 1)
        expectMatchesRebuild(patched, text: text, "delete only the newline")
    }

    @Test("inserting a newline adds a line")
    func insertNewline() {
        let index = FilePreviewLineIndex(text: "abcd" as NSString, generation: 1)
        let text = "ab\ncd" as NSString
        let patched = index.patched(
            editedRange: NSRange(location: 2, length: 0), changeInLength: 1, text: text
        )
        #expect(patched.lineCount == 2)
        expectMatchesRebuild(patched, text: text, "insert newline")
    }

    @Test("a later edit folds only the entries it passes")
    func forwardEditsFold() {
        var index = FilePreviewLineIndex(text: "a\nb\nc\nd\n" as NSString, generation: 1)
        var text = NSMutableString(string: "a\nb\nc\nd\n")

        text.replaceCharacters(in: NSRange(location: 0, length: 0), with: "X")
        index = index.patched(editedRange: NSRange(location: 0, length: 0), changeInLength: 1, text: text)
        expectMatchesRebuild(index, text: text, "after first edit")

        text.replaceCharacters(in: NSRange(location: 5, length: 0), with: "Y")
        index = index.patched(editedRange: NSRange(location: 5, length: 0), changeInLength: 1, text: text)
        expectMatchesRebuild(index, text: text, "after forward edit")
    }

    @Test("an edit that moves the boundary backward folds everything")
    func backwardEditFolds() {
        var index = FilePreviewLineIndex(text: "a\nb\nc\nd\n" as NSString, generation: 1)
        var text = NSMutableString(string: "a\nb\nc\nd\n")

        text.replaceCharacters(in: NSRange(location: 6, length: 0), with: "Z")
        index = index.patched(editedRange: NSRange(location: 6, length: 0), changeInLength: 1, text: text)
        expectMatchesRebuild(index, text: text, "after late edit")

        text.replaceCharacters(in: NSRange(location: 1, length: 0), with: "W")
        index = index.patched(editedRange: NSRange(location: 1, length: 0), changeInLength: 1, text: text)
        expectMatchesRebuild(index, text: text, "after backward edit")
    }

    @Test("random edit sequences stay identical to a full rebuild")
    func randomEditsMatchRebuild() {
        var rng = SeededRandom(seed: 0xC0FF_EE00_1234_5678)
        let alphabet: [String] = ["a", "b", "\n", "cd", "\n\n", "😀", "\r\n", ""]

        for trial in 0..<40 {
            let text = NSMutableString(string: "alpha\nbeta\ngamma\ndelta\n")
            var index = FilePreviewLineIndex(text: text, generation: trial)

            for step in 0..<12 {
                let location = Int.random(in: 0...text.length, using: &rng)
                let maxLength = text.length - location
                let length = maxLength > 0 ? Int.random(in: 0...min(3, maxLength), using: &rng) : 0
                let replacement = alphabet[Int.random(in: 0..<alphabet.count, using: &rng)]
                let delta = (replacement as NSString).length - length

                text.replaceCharacters(in: NSRange(location: location, length: length), with: replacement)
                index = index.patched(
                    editedRange: NSRange(location: location, length: length),
                    changeInLength: delta,
                    text: text
                )
                expectMatchesRebuild(index, text: text, "trial \(trial) step \(step)")
            }
        }
    }
}
