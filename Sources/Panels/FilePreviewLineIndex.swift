import Foundation

/// Maps a UTF-16 offset to a 1-based logical line number in O(log n).
///
/// Counting newlines from the top of the document on every draw would be O(n) per
/// frame, which defeats the point of `allowsNonContiguousLayout = true` on the
/// editor's layout manager. This keeps the line starts in a sorted array and binary
/// searches it.
///
/// ## Deferred shift
///
/// Naively re-shifting every entry after an edit writes the whole tail on each
/// keystroke — roughly 4 MB of `[Int]` for a 500k-line file, with no copy-on-write
/// relief because the array is uniquely referenced. Instead the tail keeps its
/// pre-edit values and a single `(shiftBoundary, pendingShift)` pair records the
/// adjustment, applied during lookup. Edits that add or remove no newline are
/// therefore O(log n), which is the overwhelmingly common case while typing.
///
/// ## Generation
///
/// Building the index off the main actor means a keystroke can land while a build is
/// in flight. ``generation`` lets the caller drop a stale index instead of installing
/// it: a mismatched index produces line numbers that look plausible but sit next to
/// the wrong rows, which is nearly invisible by eye and has to be caught in tests.
///
/// ```swift
/// let index = FilePreviewLineIndex(text: "a\nbb\n" as NSString, generation: 1)
/// index.lineCount                          // 3 — trailing newline opens a final empty line
/// index.lineNumber(atUTF16Offset: 3)       // 2
/// index.isLineStart(utf16Offset: 2)        // true
/// ```
struct FilePreviewLineIndex: Sendable, Equatable {
    /// UTF-16 offsets of each logical line start, before ``pendingShift`` is applied.
    private let lineStarts: [Int]

    /// First index whose stored value still needs ``pendingShift`` added.
    private let shiftBoundary: Int

    /// Amount owed to every entry from ``shiftBoundary`` onward.
    private let pendingShift: Int

    /// Text generation this index was built from; compare before installing.
    let generation: Int

    /// Builds an index over the whole document.
    ///
    /// - Parameters:
    ///   - text: Document to scan.
    ///   - generation: Caller's text generation counter.
    init(text: NSString, generation: Int) {
        self.init(
            lineStarts: Self.scanLineStarts(in: text, range: NSRange(location: 0, length: text.length), from: 0),
            shiftBoundary: 0,
            pendingShift: 0,
            generation: generation
        )
    }

    private init(lineStarts: [Int], shiftBoundary: Int, pendingShift: Int, generation: Int) {
        self.lineStarts = lineStarts
        self.shiftBoundary = shiftBoundary
        self.pendingShift = pendingShift
        self.generation = generation
    }

    /// Number of logical lines; always at least 1, even for empty text.
    ///
    /// A trailing newline opens a final empty line, matching how editors let you put
    /// the caret below the last visible character.
    var lineCount: Int { lineStarts.count }

    /// Returns the 1-based logical line containing `offset`.
    ///
    /// Offsets past the end clamp to the last line, so a caret at the very end of the
    /// document still reports a line.
    ///
    /// - Parameter offset: UTF-16 offset into the document.
    /// - Returns: 1-based line number.
    func lineNumber(atUTF16Offset offset: Int) -> Int {
        guard offset > 0 else { return 1 }
        var low = 0
        var high = lineStarts.count - 1
        var result = 0
        while low <= high {
            let mid = low + (high - low) / 2
            if resolvedStart(at: mid) <= offset {
                result = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        return result + 1
    }

    /// Returns whether `utf16Offset` is exactly a logical line start.
    ///
    /// The ruler uses this to draw one number per logical line: a wrapped display line
    /// begins mid-line and therefore answers `false`.
    ///
    /// - Parameter utf16Offset: UTF-16 offset into the document.
    /// - Returns: `true` when a logical line begins here.
    func isLineStart(utf16Offset: Int) -> Bool {
        var low = 0
        var high = lineStarts.count - 1
        while low <= high {
            let mid = low + (high - low) / 2
            let value = resolvedStart(at: mid)
            if value == utf16Offset {
                return true
            } else if value < utf16Offset {
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        return false
    }

    /// Returns the index updated for one edit, reusing the tail when possible.
    ///
    /// Takes the fast path — adjusting only `(shiftBoundary, pendingShift)` — when the
    /// edit neither spans an existing line start nor introduces a newline, because then
    /// the set of line starts is unchanged and only their offsets move. Otherwise
    /// rebuilds, which is correct but O(n).
    ///
    /// - Parameters:
    ///   - editedRange: Range in the **pre-edit** text that was replaced.
    ///   - changeInLength: Post-edit length minus pre-edit length.
    ///   - text: The **post-edit** document.
    /// - Returns: An index describing `text`, carrying the same ``generation``.
    func patched(editedRange: NSRange, changeInLength: Int, text: NSString) -> FilePreviewLineIndex {
        let editStart = editedRange.location
        let oldEnd = editedRange.location + editedRange.length
        let newEnd = editStart + editedRange.length + changeInLength

        // A line start at `v` exists because there is a newline at `v - 1`, so the
        // deletion removes it exactly when `v - 1` falls in `[editStart, oldEnd)` —
        // that is, when `v` is in `(editStart, oldEnd]`. The upper bound is inclusive;
        // excluding it lets "delete just the newline" slip into the fast path and keep
        // a line that no longer exists.
        let candidate = firstIndex(afterOffset: editStart)
        let spansExistingStart = candidate < lineStarts.count && resolvedStart(at: candidate) <= oldEnd

        let insertedRange = NSRange(location: editStart, length: max(0, newEnd - editStart))
        let introducesNewline = Self.containsNewline(in: text, range: insertedRange)

        guard !spansExistingStart, !introducesNewline else {
            return FilePreviewLineIndex(text: text, generation: generation)
        }

        guard changeInLength != 0 else { return self }

        // A line start at `v` exists because of the newline at `v - 1`, so it moves only
        // when that newline moves: `v - 1 >= oldEnd`, i.e. `v >= oldEnd + 1`. Using
        // `oldEnd` directly would shift offset 0 whenever text is inserted at the very
        // top, pushing the first line start off zero even though line 1 still begins
        // where it always did.
        return shifting(from: firstIndex(atOrAfterOffset: oldEnd + 1), by: changeInLength)
    }

    /// Returns the first index whose offset is strictly greater than `offset`.
    private func firstIndex(afterOffset offset: Int) -> Int {
        var low = 0
        var high = lineStarts.count
        while low < high {
            let mid = low + (high - low) / 2
            if resolvedStart(at: mid) > offset { high = mid } else { low = mid + 1 }
        }
        return low
    }

    /// Returns the first index whose offset is greater than or equal to `offset`.
    private func firstIndex(atOrAfterOffset offset: Int) -> Int {
        var low = 0
        var high = lineStarts.count
        while low < high {
            let mid = low + (high - low) / 2
            if resolvedStart(at: mid) >= offset { high = mid } else { low = mid + 1 }
        }
        return low
    }

    /// Returns whether `range` of `text` contains a newline.
    private static func containsNewline(in text: NSString, range: NSRange) -> Bool {
        let clamped = NSIntersectionRange(range, NSRange(location: 0, length: text.length))
        guard clamped.length > 0 else { return false }
        return text.range(of: "\n", options: [.literal], range: clamped).location != NSNotFound
    }

    /// Returns the true offset of `index`, applying any pending shift.
    private func resolvedStart(at index: Int) -> Int {
        index >= shiftBoundary ? lineStarts[index] + pendingShift : lineStarts[index]
    }

    /// Returns a copy where entries from `boundary` onward owe `delta` more.
    ///
    /// Folding is confined to the entries between the old and new boundary; only a
    /// boundary that moves backward forces folding the whole array, which happens when
    /// an edit lands before a previous one.
    private func shifting(from boundary: Int, by delta: Int) -> FilePreviewLineIndex {
        if boundary == shiftBoundary {
            return FilePreviewLineIndex(
                lineStarts: lineStarts,
                shiftBoundary: shiftBoundary,
                pendingShift: pendingShift + delta,
                generation: generation
            )
        }

        var folded = lineStarts
        if boundary > shiftBoundary {
            for index in shiftBoundary..<min(boundary, folded.count) {
                folded[index] += pendingShift
            }
            return FilePreviewLineIndex(
                lineStarts: folded,
                shiftBoundary: boundary,
                pendingShift: pendingShift + delta,
                generation: generation
            )
        }

        for index in shiftBoundary..<folded.count {
            folded[index] += pendingShift
        }
        return FilePreviewLineIndex(
            lineStarts: folded,
            shiftBoundary: boundary,
            pendingShift: delta,
            generation: generation
        )
    }

    /// Returns offsets just past each newline within `range`, plus offset 0 when scanning from the top.
    ///
    /// A CRLF pair yields one start, after the `\n`, so the `\r` stays part of the line
    /// it terminates — the same grouping TextKit uses for line fragments.
    private static func scanLineStarts(in text: NSString, range: NSRange, from origin: Int) -> [Int] {
        var starts: [Int] = origin == 0 ? [0] : []
        guard range.length > 0 else { return starts }
        let clamped = NSIntersectionRange(range, NSRange(location: 0, length: text.length))
        guard clamped.length > 0 else { return starts }

        var searchRange = clamped
        while searchRange.length > 0 {
            let found = text.range(of: "\n", options: [.literal], range: searchRange)
            guard found.location != NSNotFound else { break }
            let next = found.location + found.length
            if next <= text.length {
                starts.append(next)
            }
            let consumed = next - searchRange.location
            searchRange = NSRange(
                location: next,
                length: max(0, searchRange.length - consumed)
            )
        }
        return starts
    }
}
