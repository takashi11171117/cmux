import AppKit
import Foundation
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

@MainActor
@Suite("FilePreviewSyntaxHighlightController", .serialized)
struct FilePreviewSyntaxHighlightControllerTests {
    /// Engine stub that records every request and replays canned runs.
    private actor RecordingEngine: FilePreviewSyntaxHighlighting {
        struct Call: Sendable, Equatable {
            let text: String
            let language: String
            let range: NSRange
        }

        private var recorded: [Call] = []
        private var stubbed: [FilePreviewHighlightRun] = []

        init(stubbed: [FilePreviewHighlightRun] = []) {
            self.stubbed = stubbed
        }

        var calls: [Call] { recorded }
        var callCount: Int { recorded.count }

        func runs(for text: String, language: String, range: NSRange) async -> [FilePreviewHighlightRun] {
            recorded.append(Call(text: text, language: language, range: range))
            return stubbed
        }
    }

    private struct Harness {
        let textView: SavingTextView
        let scrollView: NSScrollView
    }

    private func makeHarness(text: String) -> Harness {
        let textView = SavingTextView.makeFilePreviewTextView()
        textView.string = text
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        scrollView.documentView = textView
        textView.frame = NSRect(x: 0, y: 0, width: 600, height: 4000)
        scrollView.layoutSubtreeIfNeeded()
        return Harness(textView: textView, scrollView: scrollView)
    }

    private func makeController(
        engine: any FilePreviewSyntaxHighlighting,
        policy: FilePreviewHighlightPolicy = FilePreviewHighlightPolicy(),
        filePath: String = "/tmp/sample.swift",
        isEnabled: Bool = true
    ) -> FilePreviewSyntaxHighlightController {
        FilePreviewSyntaxHighlightController(
            engine: engine,
            policy: policy,
            palette: FilePreviewHighlightPalette(background: .white, foreground: .black),
            filePath: filePath,
            isEnabled: isEnabled,
            debounce: .zero
        )
    }

    private func settle(_ controller: FilePreviewSyntaxHighlightController) async {
        await controller.debounceTask?.value
        await controller.highlightTask?.value
    }

    @Test("a document past the size budget never reaches the engine")
    func oversizedDocumentSkipsEngine() async {
        // Deliberately drives the gate through noteDocumentReplaced rather than asserting
        // on a controller built with the text already present: attach() runs when the
        // panel's text is still empty, so a gate evaluated there would always say
        // "small enough" and this protection would silently not exist.
        let engine = RecordingEngine()
        let controller = makeController(
            engine: engine, policy: FilePreviewHighlightPolicy(maximumHighlightBytes: 8)
        )
        let harness = makeHarness(text: "let value = 1\n")
        controller.attach(textView: harness.textView, scrollView: harness.scrollView)

        controller.noteDocumentReplaced(text: "let value = 1\n")
        await settle(controller)

        #expect(await engine.callCount == 0)
        #expect(controller.isHighlighting == false)
        controller.detach()
    }

    @Test("an unknown language never reaches the engine")
    func unknownLanguageSkipsEngine() async {
        let engine = RecordingEngine()
        let controller = makeController(engine: engine, filePath: "/tmp/notes.unknownext")
        let harness = makeHarness(text: "plain text\n")
        controller.attach(textView: harness.textView, scrollView: harness.scrollView)

        controller.noteDocumentReplaced(text: "plain text\n")
        await settle(controller)

        #expect(await engine.callCount == 0)
        controller.detach()
    }

    @Test("a disabled controller never reaches the engine")
    func disabledSkipsEngine() async {
        let engine = RecordingEngine()
        let controller = makeController(engine: engine, isEnabled: false)
        let harness = makeHarness(text: "let value = 1\n")
        controller.attach(textView: harness.textView, scrollView: harness.scrollView)

        controller.noteDocumentReplaced(text: "let value = 1\n")
        await settle(controller)

        #expect(await engine.callCount == 0)
        controller.detach()
    }

    @Test("the engine receives the whole document, never a slice")
    func engineReceivesWholeDocument() async {
        let text = String(repeating: "let value = 1\n", count: 400)
        let engine = RecordingEngine()
        let controller = makeController(engine: engine)
        let harness = makeHarness(text: text)
        controller.attach(textView: harness.textView, scrollView: harness.scrollView)

        controller.noteDocumentReplaced(text: text)
        await settle(controller)

        let calls = await engine.calls
        #expect(calls.count == 1)
        #expect(calls.first?.text == text)
        #expect(calls.first?.range == NSRange(location: 0, length: (text as NSString).length))
        controller.detach()
    }

    @Test("scrolling repaints from cache without re-running the engine")
    func scrollDoesNotRetokenize() async {
        // The measured reason this design caches: highlight.js scans the whole document
        // whatever range is asked for, so calling it per scroll tick would re-tokenize
        // everything each time.
        let text = String(repeating: "let value = 1\n", count: 400)
        let engine = RecordingEngine(stubbed: [
            FilePreviewHighlightRun(range: NSRange(location: 0, length: 3), role: .keyword)
        ])
        let controller = makeController(engine: engine)
        let harness = makeHarness(text: text)
        controller.attach(textView: harness.textView, scrollView: harness.scrollView)

        controller.noteDocumentReplaced(text: text)
        await settle(controller)
        let afterLoad = await engine.callCount

        harness.scrollView.contentView.scroll(to: NSPoint(x: 0, y: 1200))
        harness.scrollView.reflectScrolledClipView(harness.scrollView.contentView)
        await Task.yield()

        #expect(await engine.callCount == afterLoad)
        controller.detach()
    }

    @Test("results from a superseded generation are discarded")
    func staleResultsDiscarded() async {
        let engine = RecordingEngine(stubbed: [
            FilePreviewHighlightRun(range: NSRange(location: 0, length: 3), role: .keyword)
        ])
        let controller = makeController(engine: engine)
        let harness = makeHarness(text: "let a = 1\n")
        controller.attach(textView: harness.textView, scrollView: harness.scrollView)

        controller.noteDocumentReplaced(text: "let a = 1\n")
        // Supersede before awaiting, so the first tokenization returns against a stale
        // generation.
        controller.noteDocumentReplaced(text: "var b = 2\n")
        await settle(controller)

        let calls = await engine.calls
        #expect(calls.last?.text == "var b = 2\n")
        controller.detach()
    }

    @Test("text outside the viewport still receives the plain color")
    func offscreenTextIsPainted() async {
        // Highlighting suppresses the theme's blanket textColor assignment, so anything
        // never painted would fall back to NSTextView's default black — invisible on a
        // dark theme until the user scrolls there (FR-11 AC3).
        let text = String(repeating: "let value = 1\n", count: 800)
        let engine = RecordingEngine(stubbed: [
            FilePreviewHighlightRun(range: NSRange(location: 0, length: 3), role: .keyword)
        ])
        let controller = makeController(engine: engine)
        let harness = makeHarness(text: text)
        controller.attach(textView: harness.textView, scrollView: harness.scrollView)

        controller.noteDocumentReplaced(text: text)
        await settle(controller)

        let storage = try? #require(harness.textView.textStorage)
        let farOffset = (text as NSString).length - 5
        let color = storage?.attribute(.foregroundColor, at: farOffset, effectiveRange: nil) as? NSColor
        #expect(color != nil, "off-screen text has no foreground color, so it would draw black")
        controller.detach()
    }

    @Test("runs beyond the document are clamped instead of trapping")
    func outOfBoundsRunsAreClamped() async {
        // A single unclamped path is enough to raise NSRangeException, so the clamp is kept
        // independent of the generation check rather than relying on it.
        let text = "let a = 1\n"
        let engine = RecordingEngine(stubbed: [
            FilePreviewHighlightRun(range: NSRange(location: 0, length: 9_999), role: .keyword),
            FilePreviewHighlightRun(range: NSRange(location: 9_000, length: 5), role: .string),
        ])
        let controller = makeController(engine: engine)
        let harness = makeHarness(text: text)
        controller.attach(textView: harness.textView, scrollView: harness.scrollView)

        controller.noteDocumentReplaced(text: text)
        await settle(controller)

        #expect(harness.textView.textStorage?.length == (text as NSString).length)
        controller.detach()
    }

    @Test("turning highlighting off restores plain attributes")
    func disablingClearsAttributes() async {
        let text = "let a = 1\n"
        let engine = RecordingEngine(stubbed: [
            FilePreviewHighlightRun(range: NSRange(location: 0, length: 3), role: .keyword)
        ])
        let controller = makeController(engine: engine)
        let harness = makeHarness(text: text)
        controller.attach(textView: harness.textView, scrollView: harness.scrollView)

        controller.noteDocumentReplaced(text: text)
        await settle(controller)
        controller.setEnabled(false)

        let color = harness.textView.textStorage?
            .attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
        // Painted, not removed. `removeAttribute(.foregroundColor:)` leaves the storage with
        // no colour at all and `NSTextView` then draws its default black, which is
        // unreadable on a dark theme — see `clearAttributes()`.
        #expect(
            color == FilePreviewHighlightPalette(background: .white, foreground: .black)
                .color(for: .plain),
            "the plain colour should be painted back so the theme takes over"
        )
        let temporary = harness.textView.layoutManager?
            .temporaryAttributes(atCharacterIndex: 0, effectiveRange: nil)[.foregroundColor]
        #expect(temporary == nil, "syntax colours are display state and must not survive")
        controller.detach()
    }

    @Test("a theme change repaints without asking the engine again")
    func paletteChangeDoesNotRetokenize() async {
        let text = "let a = 1\n"
        let engine = RecordingEngine(stubbed: [
            FilePreviewHighlightRun(range: NSRange(location: 0, length: 3), role: .keyword)
        ])
        let controller = makeController(engine: engine)
        let harness = makeHarness(text: text)
        controller.attach(textView: harness.textView, scrollView: harness.scrollView)

        controller.noteDocumentReplaced(text: text)
        await settle(controller)
        let before = await engine.callCount

        controller.setPalette(FilePreviewHighlightPalette(background: .black, foreground: .white))
        await settle(controller)

        #expect(await engine.callCount == before)
        let color = harness.textView.textStorage?
            .attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
        #expect(color != nil)
        controller.detach()
    }

    @Test("detach stops the scroll subscription")
    func detachStopsSubscription() async {
        let engine = RecordingEngine()
        let controller = makeController(engine: engine)
        let harness = makeHarness(text: "let a = 1\n")
        controller.attach(textView: harness.textView, scrollView: harness.scrollView)
        controller.noteDocumentReplaced(text: "let a = 1\n")
        await settle(controller)

        controller.detach()
        let afterDetach = await engine.callCount

        harness.scrollView.contentView.scroll(to: NSPoint(x: 0, y: 500))
        harness.scrollView.reflectScrolledClipView(harness.scrollView.contentView)
        await Task.yield()

        #expect(await engine.callCount == afterDetach)
    }
}
