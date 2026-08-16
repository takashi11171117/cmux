import AppKit
import Foundation
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

/// Checks the two invariants highlighting could plausibly break in the existing editor:
/// the TextKit 1 backing, and the undo stack.
@MainActor
@Suite("File preview highlighting invariants", .serialized)
struct FilePreviewHighlightUndoAndTextKitTests {
    private actor FixedRunEngine: FilePreviewSyntaxHighlighting {
        private let runs: [FilePreviewHighlightRun]

        init(runs: [FilePreviewHighlightRun]) { self.runs = runs }

        func runs(
            for text: String, language: String, range: NSRange
        ) async -> [FilePreviewHighlightRun] {
            runs
        }
    }

    /// Supplies an undo manager to a text view that has no window.
    ///
    /// `NSResponder.undoManager` walks the responder chain up to the window, so a view
    /// assembled in a test returns nil. AppKit consults the delegate first, which is the
    /// documented seam for exactly this case.
    private final class UndoManagerProvider: NSObject, NSTextViewDelegate {
        let manager = UndoManager()

        func undoManager(for view: NSTextView) -> UndoManager? { manager }
    }

    private func makeStack(text: String) -> (SavingTextView, NSScrollView, UndoManagerProvider) {
        let textView = SavingTextView.makeFilePreviewTextView()
        let undoProvider = UndoManagerProvider()
        textView.delegate = undoProvider
        textView.string = text
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        scrollView.documentView = textView
        scrollView.layoutSubtreeIfNeeded()
        return (textView, scrollView, undoProvider)
    }

    private func makeController(
        textView: SavingTextView, scrollView: NSScrollView, text: String
    ) async -> FilePreviewSyntaxHighlightController {
        let controller = FilePreviewSyntaxHighlightController(
            engine: FixedRunEngine(runs: [
                FilePreviewHighlightRun(range: NSRange(location: 0, length: 3), role: .keyword)
            ]),
            palette: FilePreviewHighlightPalette(background: .white, foreground: .black),
            filePath: "/tmp/sample.swift",
            debounce: .zero
        )
        controller.attach(textView: textView, scrollView: scrollView)
        controller.noteDocumentReplaced(text: text)
        await controller.debounceTask?.value
        await controller.highlightTask?.value
        return controller
    }

    @Test("highlighting keeps the editor on TextKit 1")
    func highlightingKeepsTextKit1() async {
        // The hang fixed in upstream #5255 comes back the moment this view acquires a
        // textLayoutManager, so highlighting must never swap the storage or layout stack.
        // In particular this is why Highlightr's CodeAttributedString (an NSTextStorage
        // subclass) is not used.
        let text = "let value = 1\n"
        let (textView, scrollView, _) = makeStack(text: text)
        let controller = await makeController(textView: textView, scrollView: scrollView, text: text)

        #expect(textView.textLayoutManager == nil)
        #expect(textView.layoutManager != nil)
        #expect(textView.layoutManager?.allowsNonContiguousLayout == true)
        controller.detach()
    }

    @Test("applying highlight attributes does not add an undo step")
    func highlightingDoesNotPolluteUndo() async throws {
        // New-B: the design assumes attribute-only edits bypass NSTextView's undo
        // coalescing because they never go through shouldChangeText(in:replacementString:).
        // If that assumption were wrong, one Cmd-Z after a repaint would undo the color
        // instead of the typing, which is the kind of thing nobody reports precisely.
        let text = "let value = 1\n"
        let (textView, scrollView, undoProvider) = makeStack(text: text)
        let controller = await makeController(textView: textView, scrollView: scrollView, text: text)

        let undoManager = try #require(textView.undoManager)
        #expect(undoManager === undoProvider.manager)
        undoManager.removeAllActions()

        // One user-visible edit, performed the way typing does.
        let insertionRange = NSRange(location: 0, length: 0)
        #expect(textView.shouldChangeText(in: insertionRange, replacementString: "X"))
        textView.textStorage?.replaceCharacters(in: insertionRange, with: "X")
        textView.didChangeText()
        #expect(textView.string == "X" + text)

        // Repaint on top of it, several times, to make coalescing failures obvious.
        controller.noteTextDidChange(text: textView.string)
        await controller.debounceTask?.value
        await controller.highlightTask?.value
        controller.setPalette(FilePreviewHighlightPalette(background: .black, foreground: .white))
        controller.setPalette(FilePreviewHighlightPalette(background: .white, foreground: .black))

        #expect(undoManager.canUndo)
        undoManager.undo()
        #expect(
            textView.string == text,
            "one undo should retract the typed character; highlighting appears to have entered the undo stack"
        )
        controller.detach()
    }

    @Test("disabling highlighting hands the body color back to the theme")
    func disablingRestoresThemeColor() async {
        let text = "let value = 1\n"
        let (textView, scrollView, _) = makeStack(text: text)
        let controller = await makeController(textView: textView, scrollView: scrollView, text: text)

        controller.setEnabled(false)
        FilePreviewTextEditor<FilePreviewPanel>.applyTheme(
            to: scrollView,
            backgroundColor: .white,
            foregroundColor: .red,
            drawsBackground: true,
            preservesTextColor: controller.isHighlighting
        )

        let color = textView.textStorage?
            .attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
        #expect(color?.usingColorSpace(.sRGB)?.redComponent == 1.0)
        controller.detach()
    }

    @Test("theme application does not overwrite highlight colors while highlighting")
    func themeDoesNotOverwriteHighlights() async throws {
        // applyTheme runs on every SwiftUI update, and NSTextView.textColor rewrites the
        // whole storage, so without the preservesTextColor branch the first unrelated
        // state change would erase every token color.
        let text = "let value = 1\n"
        let (textView, scrollView, _) = makeStack(text: text)
        let controller = await makeController(textView: textView, scrollView: scrollView, text: text)

        let before = textView.textStorage?
            .attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
        FilePreviewTextEditor<FilePreviewPanel>.applyTheme(
            to: scrollView,
            backgroundColor: .white,
            foregroundColor: .black,
            drawsBackground: true,
            preservesTextColor: controller.isHighlighting
        )
        let after = textView.textStorage?
            .attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor

        #expect(controller.isHighlighting)
        #expect(before != nil)
        #expect(before == after, "applyTheme repainted a highlighted token back to body color")
        controller.detach()
    }
}
