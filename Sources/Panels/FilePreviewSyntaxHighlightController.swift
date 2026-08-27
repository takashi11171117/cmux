import AppKit
import Foundation

/// Drives syntax highlighting for one `NSTextView`: when to tokenize, what to repaint, and when to stop.
///
/// ## Why runs are cached instead of re-requested per scroll
///
/// The seam lets a caller ask for a narrow `range`, and the original design called the
/// engine again on every scroll with the new visible range. AFIDE-01 measured that this
/// does not work with highlight.js: clipping a 4,475-line file to 3,000 characters took
/// 231.2 ms versus 233.9 ms for the whole file, because the engine walks the document
/// regardless. Re-requesting per scroll would therefore re-tokenize the entire document
/// on every scroll tick.
///
/// So the engine runs **once per text generation** over the whole document, the runs are
/// cached, and scrolling only re-applies attributes from that cache. "Visible range first"
/// (NFR-04) is honored in the attribute-application step, which is the part that stays
/// proportional to what is on screen.
///
/// ## Generations
///
/// Every invalidation bumps ``generation``. Results arriving from the engine carry the
/// generation they were requested for and are dropped if it no longer matches, so a slow
/// tokenization of older text can never repaint newer text. Ranges are additionally
/// clamped to the live text length at apply time: one missed generation check is enough to
/// raise `NSRangeException`, and the clamp is the backstop that keeps that from crashing.
@MainActor
final class FilePreviewSyntaxHighlightController {
    private let engine: any FilePreviewSyntaxHighlighting
    private let policy: FilePreviewHighlightPolicy
    private let debounce: Duration

    private weak var textView: NSTextView?
    private weak var scrollView: NSScrollView?

    private var palette: FilePreviewHighlightPalette
    private var isEnabled: Bool
    private var filePath: String
    private var documentText: String = ""
    private var decision: FilePreviewHighlightDecision = .skippedNoLanguage

    private var generation = 0
    private var cachedRuns: [FilePreviewHighlightRun] = []
    private var cachedGeneration = -1

    private var subscriptionTask: Task<Void, Never>?

    /// In-flight debounce, exposed so tests can await it instead of sleeping.
    ///
    /// Internal rather than private for that reason alone; nothing outside tests should
    /// reach for it. A static test hook would leak across tests and need a lock, which the
    /// concurrency rules forbid — awaiting the real task is both simpler and honest about
    /// what it waits for.
    private(set) var debounceTask: Task<Void, Never>?

    /// In-flight tokenization, exposed for the same reason as ``debounceTask``.
    private(set) var highlightTask: Task<Void, Never>?

    /// Lines of context tokenized beyond the visible rect so a small scroll finds color already applied.
    private static let overscanLines = 40

    /// Creates a controller.
    ///
    /// - Parameters:
    ///   - engine: Tokenizer behind the seam.
    ///   - policy: Size and language gate.
    ///   - palette: Initial colors; replace with ``setPalette(_:)`` on theme change.
    ///   - filePath: Path used for language detection.
    ///   - isEnabled: Whether highlighting starts on.
    ///   - debounce: Quiet period after a keystroke before re-tokenizing. Pass `.zero` in
    ///     tests to make the pipeline synchronous apart from the engine hop.
    init(
        engine: any FilePreviewSyntaxHighlighting,
        policy: FilePreviewHighlightPolicy = FilePreviewHighlightPolicy(),
        palette: FilePreviewHighlightPalette,
        filePath: String,
        isEnabled: Bool = true,
        debounce: Duration = .milliseconds(120)
    ) {
        self.engine = engine
        self.policy = policy
        self.palette = palette
        self.filePath = filePath
        self.isEnabled = isEnabled
        self.debounce = debounce
    }

    deinit {
        subscriptionTask?.cancel()
        debounceTask?.cancel()
        highlightTask?.cancel()
    }

    /// Binds to a text view and starts following its scrolling.
    ///
    /// Deliberately does **not** evaluate the size or language gate: at `makeNSView` time
    /// the panel's text is still the empty initial value, so a decision made here would
    /// always conclude "small enough" and FR-03 would never fire in practice. The gate
    /// runs in ``noteDocumentReplaced(text:)`` instead.
    ///
    /// - Parameters:
    ///   - textView: View whose storage receives attributes.
    ///   - scrollView: Enclosing scroll view whose clip view is observed.
    func attach(textView: NSTextView, scrollView: NSScrollView) {
        self.textView = textView
        self.scrollView = scrollView

        let clipView = scrollView.contentView
        clipView.postsBoundsChangedNotifications = true

        subscriptionTask?.cancel()
        // `object:` must be this clip view. Without it the stream fires for every
        // NSView bounds change in the app — terminal surfaces included — and the
        // "no global observers" guarantee this design relies on is gone.
        let notifications = NotificationCenter.default.notifications(
            named: NSView.boundsDidChangeNotification, object: clipView
        )
        subscriptionTask = Task { [weak self] in
            for await _ in notifications {
                guard let self else { break }
                self.applyVisibleRunsNow()
            }
        }
    }

    /// Cancels every task and drops view references.
    ///
    /// The `for await` loop in ``attach(textView:scrollView:)`` keeps itself alive, so
    /// without this the controller, the text view, and the scroll view all leak when the
    /// panel closes.
    func detach() {
        subscriptionTask?.cancel()
        debounceTask?.cancel()
        highlightTask?.cancel()
        subscriptionTask = nil
        debounceTask = nil
        highlightTask = nil
        textView = nil
        scrollView = nil
    }

    /// Turns highlighting on or off, repainting to match.
    ///
    /// - Parameter enabled: Desired state.
    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        if enabled {
            invalidateAll()
        } else {
            cancelWork()
            clearAttributes()
        }
    }

    /// Replaces the palette and repaints without re-tokenizing.
    ///
    /// Roles are colorless, so a theme change reuses the cached runs.
    ///
    /// - Parameter palette: Colors for the new theme.
    func setPalette(_ palette: FilePreviewHighlightPalette) {
        self.palette = palette
        guard isEnabled else { return }
        repaintFromCache()
    }

    /// Records that the document was replaced wholesale and re-evaluates the gate.
    ///
    /// - Parameters:
    ///   - text: The new full document.
    ///   - filePath: Path to classify by; pass `nil` to keep the current one.
    func noteDocumentReplaced(text: String, filePath: String? = nil) {
        if let filePath { self.filePath = filePath }
        documentText = text
        decision = policy.decision(path: self.filePath, byteCount: text.utf8.count)
        invalidateAll()
    }

    /// Records an in-place edit and schedules re-tokenization after the debounce window.
    ///
    /// - Parameter text: The full document after the edit.
    func noteTextDidChange(text: String) {
        documentText = text
        generation += 1
        guard isEnabled, case .highlight = decision else { return }

        // Both are cancelled: a tokenization started by invalidateAll() is now describing
        // superseded text, and leaving it running would walk the whole document a second
        // time for a result the generation check throws away.
        debounceTask?.cancel()
        highlightTask?.cancel()

        let scheduled = generation
        let quietPeriod = debounce
        debounceTask = Task { [weak self] in
            if quietPeriod != .zero {
                try? await Task.sleep(for: quietPeriod)
            }
            guard !Task.isCancelled, let self else { return }
            await self.tokenize(for: scheduled)
        }
    }

    /// Bumps the generation and repaints from scratch.
    func invalidateAll() {
        generation += 1
        cachedRuns = []
        cachedGeneration = -1
        cancelWork()

        guard isEnabled else {
            clearAttributes()
            return
        }
        guard case .highlight = decision else {
            clearAttributes()
            return
        }

        paintPlainBaseline()
        let scheduled = generation
        highlightTask = Task { [weak self] in
            await self?.tokenize(for: scheduled)
        }
    }

    /// Whether the gate allows highlighting for the current document.
    ///
    /// Exposed so the owner can drop the controller entirely when the answer is no,
    /// keeping NFR-03 ("no cost when unused") honest.
    var isHighlighting: Bool {
        if case .highlight = decision { return isEnabled }
        return false
    }

    /// Runs the engine for `requestedGeneration` and caches the result if still current.
    private func tokenize(for requestedGeneration: Int) async {
        guard case .highlight(let language) = decision else { return }
        let text = documentText
        let whole = NSRange(location: 0, length: (text as NSString).length)
        guard whole.length > 0 else { return }

        let runs = await engine.runs(for: text, language: language, range: whole)

        guard requestedGeneration == generation else { return }
        cachedRuns = runs.sorted { lhs, rhs in
            lhs.range.location == rhs.range.location
                ? lhs.range.length > rhs.range.length
                : lhs.range.location < rhs.range.location
        }
        cachedGeneration = requestedGeneration
        repaintFromCache()
    }

    /// Repaints the baseline plus the visible slice of the cache.
    ///
    /// The temporary colours go first: they are keyed by range, so a palette change would
    /// otherwise leave the previous theme's colours on every range the new pass does not
    /// happen to cover.
    private func repaintFromCache() {
        clearTemporaryColors()
        paintPlainBaseline()
        applyVisibleRunsNow()
    }

    /// Applies cached runs for the current viewport, as display-only temporary attributes.
    ///
    /// Not `NSTextStorage.addAttribute`. This runs inside the clip view's bounds-change
    /// notification, and a storage edit there — attribute-only or not — ends in
    /// `endEditing()`, which invalidates layout, resizes the text view, and moves the clip
    /// view's bounds again. That is a feedback loop between scrolling and repainting: the
    /// document height was measured changing 7952 -> 8334 -> 8262 mid-scroll while the
    /// scroll position was pinned at 70 pixels and 36 further wheel events moved it not at
    /// all. Turning highlighting off made the same scroll run smoothly to 1750.
    ///
    /// `NSLayoutManager` temporary attributes exist for exactly this: they colour glyphs for
    /// display without touching the text storage, so nothing is invalidated and the scroll
    /// is left alone.
    private func applyVisibleRunsNow() {
        guard isEnabled, cachedGeneration == generation, !cachedRuns.isEmpty else { return }
        guard let textView,
              let storage = textView.textStorage,
              let layoutManager = textView.layoutManager
        else { return }

        let documentRange = NSRange(location: 0, length: storage.length)
        let window = NSIntersectionRange(visibleCharacterRange() ?? documentRange, documentRange)
        guard window.length > 0 else { return }

        for run in cachedRuns {
            let clamped = NSIntersectionRange(run.range, documentRange)
            guard clamped.length > 0, NSIntersectionRange(clamped, window).length > 0 else { continue }
            layoutManager.setTemporaryAttributes(
                [.foregroundColor: palette.color(for: run.role)],
                forCharacterRange: clamped
            )
        }
    }

    /// Drops every syntax colour, leaving the storage's own colour showing.
    ///
    /// Temporary attributes are display state, so this is what "unhighlight" means now;
    /// the plain baseline painted into the storage is what remains visible.
    private func clearTemporaryColors() {
        guard let textView,
              let storage = textView.textStorage,
              let layoutManager = textView.layoutManager,
              storage.length > 0
        else { return }
        layoutManager.removeTemporaryAttribute(
            .foregroundColor,
            forCharacterRange: NSRange(location: 0, length: storage.length)
        )
    }

    /// Paints the whole document in the plain color so off-screen text is never left black.
    ///
    /// Skipping this and relying on `applyTheme` would work only until the first scroll:
    /// highlighting suppresses the theme's blanket `textColor` assignment, so any region
    /// that has not been painted yet would render in `NSTextView`'s default black — which
    /// on a dark theme is unreadable (FR-11 AC3). One attribute run over the whole document
    /// is cheap even at the 16 MB ceiling.
    private func paintPlainBaseline() {
        guard let storage = textView?.textStorage, storage.length > 0 else { return }
        let whole = NSRange(location: 0, length: storage.length)
        storage.beginEditing()
        storage.addAttribute(.foregroundColor, value: palette.color(for: .plain), range: whole)
        storage.endEditing()
    }

    /// Repaints the document in the theme's body color, dropping any syntax colors.
    ///
    /// Paints rather than removes. `removeAttribute(.foregroundColor:)` leaves the storage
    /// with no color at all, and `NSTextView` then draws its default black — unreadable on a
    /// dark theme. That is what a file with no known grammar looked like: skipped by the
    /// gate, stripped of attributes, and never repainted because `applyTheme` had already
    /// run for that update.
    private func clearAttributes() {
        clearTemporaryColors()
        guard let storage = textView?.textStorage, storage.length > 0 else { return }
        let whole = NSRange(location: 0, length: storage.length)
        storage.beginEditing()
        storage.addAttribute(.foregroundColor, value: palette.color(for: .plain), range: whole)
        storage.endEditing()
    }

    private func cancelWork() {
        debounceTask?.cancel()
        highlightTask?.cancel()
        debounceTask = nil
        highlightTask = nil
    }

    /// Returns the character range on screen plus overscan, or `nil` when unavailable.
    private func visibleCharacterRange() -> NSRange? {
        guard
            let textView,
            let layoutManager = textView.layoutManager,
            let container = textView.textContainer,
            let scrollView
        else { return nil }

        let visibleRect = scrollView.contentView.documentVisibleRect
        guard !visibleRect.isEmpty else { return nil }

        let glyphRange = layoutManager.glyphRange(forBoundingRect: visibleRect, in: container)
        var actualGlyphRange = NSRange()
        let charRange = layoutManager.characterRange(
            forGlyphRange: glyphRange, actualGlyphRange: &actualGlyphRange
        )

        let storageLength = textView.textStorage?.length ?? 0
        let padding = Self.overscanLines * 80
        let start = max(0, charRange.location - padding)
        let end = min(storageLength, charRange.location + charRange.length + padding)
        return NSRange(location: start, length: max(0, end - start))
    }
}
