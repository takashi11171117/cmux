import AppKit
import CmuxFoundation
import Foundation

/// Draws logical line numbers in the editor's left margin.
///
/// Built on `NSRulerView` so AppKit owns scroll synchronization, coordinate conversion,
/// and `clientView` tracking. The alternatives all lose something: a sibling `NSView`
/// synced by hand drifts during rubber-band scrolling; drawing inside the text view's
/// background scrolls the numbers away horizontally; and inserting numbers as text would
/// corrupt what gets saved.
///
/// ## One number per logical line
///
/// With `fileEditor.wordWrap` on, a long line occupies several line fragments. Numbering
/// each fragment would imply the file has more lines than it does, so the ruler asks
/// ``FilePreviewLineIndex`` whether a fragment actually starts a logical line and skips
/// continuations.
///
/// ## Why this is also the text-storage delegate
///
/// The ruler needs `editedRange` and `changeInLength` to update the index incrementally;
/// only `NSTextStorageDelegate` supplies them. Rebuilding from `textDidChange` instead
/// would be O(n) per keystroke, which is what the index exists to avoid. The storage had
/// no delegate before this, and the ruler keeps ownership rather than adding another
/// stored property to `SavingTextView`.
final class FilePreviewLineNumberRulerView: NSRulerView, NSTextStorageDelegate {
    private var lineIndex: FilePreviewLineIndex
    private var lastLineCount = 0
    private var lastMeasuredFont: NSFont?
    private var numberFont: NSFont

    /// Horizontal padding on each side of the digits.
    private static let horizontalPadding: CGFloat = 8
    /// Narrowest gutter, in digits, so single-digit files still look deliberate.
    private static let minimumDigits = 3

    /// Creates a ruler bound to `textView` and starts observing its storage.
    ///
    /// - Parameters:
    ///   - scrollView: Scroll view the ruler belongs to.
    ///   - textView: Text view whose lines are numbered.
    init(scrollView: NSScrollView, textView: NSTextView) {
        let storage = textView.textStorage
        lineIndex = FilePreviewLineIndex(
            text: (storage?.string ?? "") as NSString, generation: 0
        )
        numberFont = textView.font ?? NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        super.init(scrollView: scrollView, orientation: .verticalRuler)
        clientView = textView
        storage?.delegate = self
        recalculateThickness()
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) is not used; the ruler is created programmatically")
    }

    /// Number of logical lines the ruler currently believes the document has.
    ///
    /// Exposed so the incremental index can be checked without rendering; drawing is the
    /// only other observable effect and it cannot be asserted on cheaply.
    var numberedLineCount: Int { lineIndex.lineCount }

    /// Returns whether `utf16Offset` begins a logical line, per the ruler's index.
    ///
    /// This is the predicate that suppresses numbers on wrapped continuations.
    func startsLogicalLine(atUTF16Offset utf16Offset: Int) -> Bool {
        lineIndex.isLineStart(utf16Offset: utf16Offset)
    }

    /// Adopts the editor's current font and re-measures the gutter.
    ///
    /// Called from `applyCurrentPreviewFont()`, the single point every zoom path converges
    /// on (pinch, modifier-scroll, smart zoom, keyboard shortcut, and the app-wide
    /// magnification observer), so the ruler cannot drift out of step with the body text.
    ///
    /// - Parameter font: Font the text view now uses.
    func adoptFont(_ font: NSFont) {
        numberFont = font
        recalculateThickness()
        needsDisplay = true
    }

    /// Rebuilds the index from scratch, for when the whole document was replaced.
    ///
    /// - Parameter text: The new document.
    func resetIndex(text: NSString) {
        lineIndex = FilePreviewLineIndex(text: text, generation: lineIndex.generation + 1)
        recalculateThickness()
        needsDisplay = true
    }

    func textStorage(
        _ textStorage: NSTextStorage,
        didProcessEditing editedMask: NSTextStorageEditActions,
        range editedRange: NSRange,
        changeInLength delta: Int
    ) {
        guard editedMask.contains(.editedCharacters) else { return }

        // `editedRange` is expressed in the **post-edit** text, while the index patches
        // from the **pre-edit** range. They differ by exactly `delta`.
        let preEditRange = NSRange(
            location: editedRange.location,
            length: max(0, editedRange.length - delta)
        )
        lineIndex = lineIndex.patched(
            editedRange: preEditRange,
            changeInLength: delta,
            text: textStorage.string as NSString
        )
        recalculateThickness()
        needsDisplay = true
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard
            let textView = clientView as? NSTextView,
            let layoutManager = textView.layoutManager,
            let container = textView.textContainer
        else { return }

        let visibleRect = scrollView?.contentView.documentVisibleRect ?? textView.visibleRect
        let glyphRange = layoutManager.glyphRange(forBoundingRect: visibleRect, in: container)
        guard glyphRange.length > 0 else { return }

        let attributes: [NSAttributedString.Key: Any] = [
            .font: numberFont,
            .foregroundColor: NSColor.secondaryLabelColor,
        ]
        let inset = textView.textContainerInset
        let thickness = ruleThickness

        layoutManager.enumerateLineFragments(forGlyphRange: glyphRange) {
            [weak self] _, usedRect, _, fragmentGlyphRange, _ in
            guard let self else { return }

            let characterRange = layoutManager.characterRange(
                forGlyphRange: fragmentGlyphRange, actualGlyphRange: nil
            )
            // A wrapped continuation begins mid-line, so it is not a logical line start.
            guard self.lineIndex.isLineStart(utf16Offset: characterRange.location) else { return }

            let number = self.lineIndex.lineNumber(atUTF16Offset: characterRange.location)
            let label = String(number) as NSString
            let size = label.size(withAttributes: attributes)
            let y = usedRect.minY + inset.height - visibleRect.minY
            let origin = NSPoint(x: thickness - size.width - Self.horizontalPadding, y: y)
            label.draw(at: origin, withAttributes: attributes)
        }
    }

    /// Widens or narrows the gutter to fit the largest line number.
    ///
    /// `NSScrollView` reclaims the width from the document view, so a wider gutter never
    /// clips the text; it reflows it.
    private func recalculateThickness() {
        let count = lineIndex.lineCount
        // Both inputs matter. Keying only on the line count meant a zoom kept the gutter
        // measured for the old font, so the digits drifted out of the space reserved for them.
        let unchanged = count == lastLineCount && lastMeasuredFont == numberFont && ruleThickness > 0
        guard !unchanged else { return }
        lastLineCount = count
        lastMeasuredFont = numberFont

        let digits = max(Self.minimumDigits, String(count).count)
        let sample = String(repeating: "8", count: digits) as NSString
        let width = sample.size(withAttributes: [.font: numberFont]).width
        ruleThickness = ceil(width) + Self.horizontalPadding * 2
    }
}
