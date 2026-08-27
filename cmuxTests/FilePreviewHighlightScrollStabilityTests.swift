import AppKit
import Foundation
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

/// Syntax colouring must be display-only, so scrolling never edits the document.
///
/// The bug this pins down: colours were applied with `NSTextStorage.addAttribute` from
/// inside the clip view's bounds-change notification. `endEditing()` invalidates layout, the
/// text view resizes, the clip view's bounds move again — a feedback loop between scrolling
/// and repainting. Measured in the running app, the document height changed 7952 -> 8334 ->
/// 8262 mid-scroll while the scroll position stayed pinned at 70 points through 36 further
/// wheel events. The same scroll with highlighting disabled ran smoothly to 1750.
@MainActor
@Suite("File preview highlight scroll stability", .serialized)
struct FilePreviewHighlightScrollStabilityTests {
    private actor StubEngine: FilePreviewSyntaxHighlighting {
        private let stubbed: [FilePreviewHighlightRun]
        init(stubbed: [FilePreviewHighlightRun]) { self.stubbed = stubbed }
        func runs(for text: String, language: String, range: NSRange) async -> [FilePreviewHighlightRun] {
            stubbed
        }
    }

    private let palette = FilePreviewHighlightPalette(background: .white, foreground: .black)
    private let keywordRange = NSRange(location: 0, length: 3)

    private func makeAttached(
        text: String
    ) -> (SavingTextView, NSScrollView, FilePreviewSyntaxHighlightController) {
        let textView = SavingTextView.makeFilePreviewTextView()
        textView.string = text
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        scrollView.documentView = textView
        textView.frame = NSRect(x: 0, y: 0, width: 600, height: 4000)
        scrollView.layoutSubtreeIfNeeded()

        let controller = FilePreviewSyntaxHighlightController(
            engine: StubEngine(stubbed: [
                FilePreviewHighlightRun(range: keywordRange, role: .keyword),
            ]),
            policy: FilePreviewHighlightPolicy(),
            palette: palette,
            filePath: "/tmp/sample.swift",
            isEnabled: true,
            debounce: .zero
        )
        controller.attach(textView: textView, scrollView: scrollView)
        return (textView, scrollView, controller)
    }

    private func settle(_ controller: FilePreviewSyntaxHighlightController) async {
        await controller.debounceTask?.value
        await controller.highlightTask?.value
    }

    @Test("Colouring a token leaves the text storage untouched")
    func colouringDoesNotWriteToTextStorage() async {
        let (textView, _, controller) = makeAttached(text: "let value = 1\n")
        controller.noteDocumentReplaced(text: textView.string)
        await settle(controller)

        let storageColor = textView.textStorage?.attribute(
            .foregroundColor, at: 0, effectiveRange: nil
        ) as? NSColor

        // Not the keyword colour: if this is the keyword colour, the colour went into the
        // document, which is what makes scrolling invalidate layout.
        #expect(storageColor != palette.color(for: .keyword))
        #expect(storageColor == palette.color(for: .plain))
        controller.detach()
    }

    @Test("The token is coloured, as a layout-manager temporary attribute")
    func colouringUsesTemporaryAttributes() async {
        let (textView, _, controller) = makeAttached(text: "let value = 1\n")
        controller.noteDocumentReplaced(text: textView.string)
        await settle(controller)

        let temporary = textView.layoutManager?.temporaryAttributes(
            atCharacterIndex: 0, effectiveRange: nil
        )[.foregroundColor] as? NSColor

        #expect(temporary == palette.color(for: .keyword))
        controller.detach()
    }

    @Test("Scrolling does not edit the document")
    func scrollingDoesNotEditTheDocument() async {
        let (textView, scrollView, controller) = makeAttached(text: "let value = 1\n")
        controller.noteDocumentReplaced(text: textView.string)
        await settle(controller)

        var edits = 0
        let observer = NotificationCenter.default.addObserver(
            forName: NSTextStorage.didProcessEditingNotification,
            object: textView.textStorage,
            queue: nil
        ) { _ in edits += 1 }
        defer { NotificationCenter.default.removeObserver(observer) }

        // What a wheel tick amounts to: the clip view's bounds move, which is the signal the
        // controller subscribes to.
        for offset in stride(from: CGFloat(0), through: 300, by: 60) {
            scrollView.contentView.scroll(to: NSPoint(x: 0, y: offset))
            scrollView.reflectScrolledClipView(scrollView.contentView)
            await Task.yield()
        }

        // One edit here is one layout invalidation, and that is what pins the scroll.
        #expect(edits == 0)
        controller.detach()
    }

    @Test("Turning highlighting off drops the syntax colour")
    func disablingClearsTheTemporaryColour() async {
        let (textView, _, controller) = makeAttached(text: "let value = 1\n")
        controller.noteDocumentReplaced(text: textView.string)
        await settle(controller)

        controller.setEnabled(false)
        await settle(controller)

        let temporary = textView.layoutManager?.temporaryAttributes(
            atCharacterIndex: 0, effectiveRange: nil
        )[.foregroundColor] as? NSColor

        // Temporary attributes are display state, so leaving them behind would keep a
        // disabled editor looking highlighted.
        #expect(temporary == nil)
        controller.detach()
    }
}
