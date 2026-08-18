import AppKit
import CmuxFoundation
import CmuxSettings
import SwiftUI

@MainActor
protocol FilePreviewTextEditingPanel: AnyObject {
    var textContent: String { get }

    func attachTextView(_ textView: NSTextView)
    func retryPendingFocus()
    func updateTextContent(_ nextContent: String)
    @discardableResult
    func saveTextContent() -> Task<Void, Never>?
}

struct FilePreviewTextEditor<PanelModel>: NSViewRepresentable where PanelModel: ObservableObject & FilePreviewTextEditingPanel {
    @ObservedObject var panel: PanelModel
    let isVisibleInUI: Bool
    let themeBackgroundColor: NSColor
    let themeForegroundColor: NSColor
    let drawsBackground: Bool
    /// Whether long lines soft-wrap at the editor's right edge. Sourced from
    /// the persisted `fileEditor.wordWrap` setting; updates apply live.
    let wordWrap: Bool
    /// Path of the edited file, used to pick a highlighting grammar by extension.
    ///
    /// Passed in rather than read off the panel because ``FilePreviewTextEditingPanel``
    /// intentionally exposes only editing operations, and both conforming panels already
    /// know their own path.
    let filePath: String
    /// Whether tokens are colored. Sourced from `fileEditor.syntaxHighlight`; live.
    let syntaxHighlight: Bool
    /// Whether the line-number ruler is drawn. Sourced from `fileEditor.lineNumbers`; live.
    let lineNumbers: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(panel: panel)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.isHidden = !isVisibleInUI
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = drawsBackground

        let textView = SavingTextView.makeFilePreviewTextView()
        textView.panel = panel
        textView.delegate = context.coordinator
        textView.drawsBackground = drawsBackground
        textView.string = panel.textContent
        panel.attachTextView(textView)

        scrollView.documentView = textView
        textView.applyFilePreviewWordWrap(wordWrap, scrollView: scrollView)

        scrollView.hasVerticalRuler = true
        scrollView.verticalRulerView = FilePreviewLineNumberRulerView(
            scrollView: scrollView, textView: textView
        )
        scrollView.rulersVisible = lineNumbers

        // Attaching here binds the scroll observer, but the size/language gate runs later:
        // `panel.textContent` is still the empty initial value at this point, so a gate
        // evaluated now would always conclude "small enough" and never fire in practice.
        context.coordinator.syncHighlightController(
            enabled: syntaxHighlight,
            filePath: filePath,
            palette: FilePreviewHighlightPalette(
                background: themeBackgroundColor, foreground: themeForegroundColor
            ),
            textView: textView,
            scrollView: scrollView
        )

        Self.applyTheme(
            to: scrollView,
            backgroundColor: themeBackgroundColor,
            foregroundColor: themeForegroundColor,
            drawsBackground: drawsBackground,
            preservesTextColor: context.coordinator.highlightController?.isHighlighting ?? false
        )
        return scrollView
    }

    static func dismantleNSView(_ scrollView: NSScrollView, coordinator: Coordinator) {
        // The scroll subscription's `for await` loop retains itself, so without this the
        // controller, text view, and scroll view all outlive the closed panel.
        coordinator.highlightController?.detach()
        coordinator.highlightController = nil
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.panel = panel
        scrollView.isHidden = !isVisibleInUI

        guard let textView = scrollView.documentView as? SavingTextView else {
            Self.applyTheme(
                to: scrollView,
                backgroundColor: themeBackgroundColor,
                foregroundColor: themeForegroundColor,
                drawsBackground: drawsBackground,
                preservesTextColor: false
            )
            return
        }

        // Reconcile the controller *before* applying the theme: turning highlighting off
        // has to be visible to `preservesTextColor` in the same pass, otherwise the blanket
        // `textColor` assignment is skipped for one update and stale colors linger.
        context.coordinator.syncHighlightController(
            enabled: syntaxHighlight,
            filePath: filePath,
            palette: FilePreviewHighlightPalette(
                background: themeBackgroundColor, foreground: themeForegroundColor
            ),
            textView: textView,
            scrollView: scrollView
        )

        Self.applyTheme(
            to: scrollView,
            backgroundColor: themeBackgroundColor,
            foregroundColor: themeForegroundColor,
            drawsBackground: drawsBackground,
            preservesTextColor: context.coordinator.highlightController?.isHighlighting ?? false
        )
        textView.panel = panel
        textView.applyFilePreviewTextEditorInsets()
        textView.applyFilePreviewWordWrap(wordWrap, scrollView: scrollView)
        // Toggling `rulersVisible` re-lays out the scroll view, so only do it on a real
        // change; `updateNSView` runs far more often than the setting changes.
        if scrollView.rulersVisible != lineNumbers {
            scrollView.rulersVisible = lineNumbers
        }
        // Wrapping changes which fragments start a logical line, so the ruler has to redraw
        // even though the text itself did not change. Marking it dirty is cheap and does not
        // disturb layout, unlike the assignments above.
        scrollView.verticalRulerView?.needsDisplay = true
        panel.attachTextView(textView)
        guard textView.string != panel.textContent else { return }
        let selectedRanges = textView.selectedRanges
        let visibleOrigin = scrollView.contentView.bounds.origin
        context.coordinator.isApplyingPanelUpdate = true
        textView.string = panel.textContent
        context.coordinator.isApplyingPanelUpdate = false
        let contentLength = (textView.string as NSString).length
        let clampedRanges = selectedRanges.map { value -> NSValue in
            let range = value.rangeValue
            let location = min(range.location, contentLength)
            let length = min(range.length, contentLength - location)
            return NSValue(range: NSRange(location: location, length: length))
        }
        textView.setSelectedRanges(clampedRanges, affinity: .downstream, stillSelecting: false)
        scrollView.layoutSubtreeIfNeeded()
        let clipView = scrollView.contentView
        let constrained = clipView.constrainBoundsRect(
            NSRect(origin: visibleOrigin, size: clipView.bounds.size)
        )
        clipView.scroll(to: constrained.origin)
        scrollView.reflectScrolledClipView(clipView)

        // Assigning `textView.string` wipes every attribute in the storage, so this is both
        // where the gate is evaluated and where re-highlighting has to be triggered.
        context.coordinator.highlightController?.noteDocumentReplaced(
            text: textView.string, filePath: filePath
        )
        // Incremental patching cannot describe a wholesale replacement, so the index is
        // rebuilt rather than patched here.
        (scrollView.verticalRulerView as? FilePreviewLineNumberRulerView)?
            .resetIndex(text: textView.string as NSString)
    }

    /// Applies editor chrome colors.
    ///
    /// - Parameter preservesTextColor: When `true`, skips the blanket `textView.textColor`
    ///   assignment. That setter rewrites `.foregroundColor` across the entire storage, and
    ///   because this runs on every SwiftUI update it would repaint syntax colors back to
    ///   body color on the next unrelated state change. New typing still picks up the body
    ///   color through `typingAttributes`, and the highlight controller paints the body
    ///   color across the document itself.
    static func applyTheme(
        to scrollView: NSScrollView,
        backgroundColor: NSColor,
        foregroundColor: NSColor,
        drawsBackground: Bool,
        preservesTextColor: Bool = false
    ) {
        let resolvedBackgroundColor = drawsBackground ? backgroundColor : .clear
        scrollView.drawsBackground = drawsBackground
        scrollView.backgroundColor = resolvedBackgroundColor
        scrollView.contentView.drawsBackground = drawsBackground
        scrollView.contentView.backgroundColor = resolvedBackgroundColor
        if let textView = scrollView.documentView as? NSTextView {
            textView.drawsBackground = drawsBackground
            textView.backgroundColor = resolvedBackgroundColor
            if preservesTextColor {
                textView.typingAttributes[.foregroundColor] = foregroundColor
            } else {
                textView.textColor = foregroundColor
            }
            textView.insertionPointColor = foregroundColor
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var panel: PanelModel
        var isApplyingPanelUpdate = false
        var highlightController: FilePreviewSyntaxHighlightController?

        init(panel: PanelModel) {
            self.panel = panel
        }

        deinit {}

        /// Creates, updates, or tears down the controller to match `enabled`.
        ///
        /// Creating lazily rather than always means an editor with highlighting switched
        /// off constructs nothing at all, which is what NFR-03 asks for.
        @MainActor
        func syncHighlightController(
            enabled: Bool,
            filePath: String,
            palette: FilePreviewHighlightPalette,
            textView: NSTextView,
            scrollView: NSScrollView
        ) {
            guard enabled else {
                highlightController?.setEnabled(false)
                highlightController?.detach()
                highlightController = nil
                return
            }

            if let controller = highlightController {
                controller.setEnabled(true)
                controller.setPalette(palette)
                return
            }

            let controller = FilePreviewSyntaxHighlightController(
                engine: FilePreviewHighlightJavaScriptEngine(),
                palette: palette,
                filePath: filePath
            )
            controller.attach(textView: textView, scrollView: scrollView)
            highlightController = controller
            if !textView.string.isEmpty {
                controller.noteDocumentReplaced(text: textView.string, filePath: filePath)
            }
        }

        func textDidChange(_ notification: Notification) {
            guard !isApplyingPanelUpdate,
                  let textView = notification.object as? NSTextView else { return }
            panel.updateTextContent(textView.string)
            highlightController?.noteTextDidChange(text: textView.string)
        }
    }
}

enum FilePreviewTextEditorLayout {
    static let textContainerInset = NSSize(width: 12, height: 10)
    static let lineFragmentPadding: CGFloat = 0
}

extension SavingTextView {
    /// Builds the File Preview text view configured for large plain-text files.
    ///
    /// File Preview opens files up to `FilePreviewPanel.maximumLoadedTextBytes` (16 MB), which can
    /// be hundreds of thousands of lines. Selection responsiveness on that content is the reason
    /// this configuration is centralized; see `manaflow-ai/cmux#4576`.
    static func makeFilePreviewTextView() -> SavingTextView {
        // Build an EXPLICIT TextKit 1 stack so this view is never TextKit 2.
        //
        // A default `NSTextView()` is TextKit 2: selection/hit-testing then runs through
        // `NSTextSelectionNavigation`, whose work is O(N) in line-fragment count, so clicking or
        // drag-selecting in a large document pegs the main thread inside AppKit's modal
        // mouse-tracking loop and freezes the whole app (`manaflow-ai/cmux#4576`, `#5255`).
        //
        // Merely *reading* `.layoutManager` afterward — the previous mitigation — only drops the
        // view to TextKit 2 *compatibility* mode: `textLayoutManager` stays non-nil and the slow
        // selection path remains active (confirmed by live `sample` captures of the hung process).
        // Constructing the view from an `NSTextStorage` / `NSLayoutManager` / `NSTextContainer`
        // stack is the only way to guarantee `textLayoutManager == nil`, i.e. a pure TextKit 1 view
        // whose hit-testing uses `NSLayoutManager` (O(log N) with non-contiguous layout).
        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        // Lazy glyph layout so multi-hundred-thousand-line documents still open instantly.
        layoutManager.allowsNonContiguousLayout = true
        textStorage.addLayoutManager(layoutManager)
        let textContainer = NSTextContainer(
            size: NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        )
        // No-wrap baseline; `applyFilePreviewWordWrap(_:scrollView:)` flips this live per the
        // `fileEditor.wordWrap` setting.
        textContainer.widthTracksTextView = false
        layoutManager.addTextContainer(textContainer)

        let textView = SavingTextView(frame: .zero, textContainer: textContainer)
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.usesFindPanel = true
        textView.usesFontPanel = false
        textView.applyCurrentPreviewFont()
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = true
        textView.autoresizingMask = [.width]
        textView.applyFilePreviewTextEditorInsets()
        return textView
    }
}

extension NSTextView {
    /// Configures the text view and its scroll view for soft line wrapping
    /// (`wrap == true`) or the no-wrap baseline with a horizontal scroller
    /// (`wrap == false`). Idempotent, so it is safe to call on every SwiftUI
    /// update; toggling the `fileEditor.wordWrap` setting reflows open editors.
    /// Applies the wrap mode, doing nothing when nothing changed.
    ///
    /// Every assignment here invalidates layout, and `updateNSView` runs on each SwiftUI
    /// pass — including passes that land mid-scroll. Re-applying identical values then
    /// resets the text view's frame under the scroller, which reads as the content bouncing
    /// back and, once the scroll view's idea of the document size goes stale, as the wheel
    /// no longer scrolling at all. Dragging the scroller keeps working, which is the tell.
    ///
    /// - Parameters:
    ///   - wrap: Whether lines wrap to the visible width.
    ///   - scrollView: The enclosing scroll view, whose horizontal scroller follows `wrap`.
    func applyFilePreviewWordWrap(_ wrap: Bool, scrollView: NSScrollView) {
        guard let textContainer else { return }
        if scrollView.hasHorizontalScroller != !wrap {
            scrollView.hasHorizontalScroller = !wrap
        }
        if isHorizontallyResizable != !wrap {
            isHorizontallyResizable = !wrap
        }
        if wrap {
            // `widthTracksTextView` keeps the container pinned to the text view
            // width, so wrapping is correct even before the scroll view is laid
            // out. Only snap the frame/container to a real measured width to
            // avoid collapsing to a zero-width container during `makeNSView`,
            // before the clip view has a size; `updateNSView` re-runs once laid
            // out and reflows.
            if !textContainer.widthTracksTextView {
                textContainer.widthTracksTextView = true
            }
            let visibleWidth = scrollView.contentSize.width
            if visibleWidth > 0, textContainer.size.width != visibleWidth {
                textContainer.size = NSSize(width: visibleWidth, height: .greatestFiniteMagnitude)
                setFrameSize(NSSize(width: visibleWidth, height: frame.height))
            }
        } else {
            if textContainer.widthTracksTextView {
                textContainer.widthTracksTextView = false
            }
            let unbounded = NSSize(
                width: CGFloat.greatestFiniteMagnitude,
                height: CGFloat.greatestFiniteMagnitude
            )
            if textContainer.size != unbounded {
                textContainer.size = unbounded
            }
        }
    }

    func applyFilePreviewTextEditorInsets() {
        let targetInset = FilePreviewTextEditorLayout.textContainerInset
        if textContainerInset.width != targetInset.width || textContainerInset.height != targetInset.height {
            textContainerInset = targetInset
        }
        if textContainer?.lineFragmentPadding != FilePreviewTextEditorLayout.lineFragmentPadding {
            textContainer?.lineFragmentPadding = FilePreviewTextEditorLayout.lineFragmentPadding
        }
    }
}

final class SavingTextView: NSTextView {
    private static let defaultPreviewFontSize: CGFloat = 13
    private static let minimumPreviewFontSize: CGFloat = 8
    private static let maximumPreviewFontSize: CGFloat = 36
    private static let previewFontZoomShortcutActions: [KeyboardShortcutSettings.Action] = [
        .browserZoomIn,
        .browserZoomOut,
        .browserZoomReset,
    ]

    weak var panel: (any FilePreviewTextEditingPanel)?
    private var previewFontSize: CGFloat = 13
    private var pendingEditorShortcutChordPrefix: ShortcutStroke?
    private var fontMagnificationObserver: GlobalFontMagnificationChangeObserver?

    convenience init() {
        self.init(frame: .zero, textContainer: nil)
    }

    override init(frame frameRect: NSRect, textContainer container: NSTextContainer?) {
        super.init(frame: frameRect, textContainer: container)
        installFontMagnificationObserver()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        installFontMagnificationObserver()
    }

    deinit {}

    private func installFontMagnificationObserver() {
        fontMagnificationObserver = GlobalFontMagnificationChangeObserver { [weak self] in
            self?.applyCurrentPreviewFont()
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        clearPendingShortcutChordPrefixes()
        applyFilePreviewTextEditorInsets()
        panel?.retryPendingFocus()
    }

    override func resignFirstResponder() -> Bool {
        let didResign = super.resignFirstResponder()
        if didResign {
            clearPendingShortcutChordPrefixes()
        }
        return didResign
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.type == .keyDown else {
            return super.performKeyEquivalent(with: event)
        }
        if handleEditorShortcut(event) {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func magnify(with event: NSEvent) {
        let factor = 1.0 + event.magnification
        guard factor.isFinite, factor > 0 else { return }
        adjustPreviewFontSize(by: factor)
    }

    override func scrollWheel(with event: NSEvent) {
        guard FilePreviewInteraction.hasZoomModifier(event) else {
            super.scrollWheel(with: event)
            return
        }
        adjustPreviewFontSize(by: FilePreviewInteraction.zoomFactor(forScroll: event))
    }

    override func smartMagnify(with event: NSEvent) {
        if previewFontSize == Self.defaultPreviewFontSize {
            _ = setPreviewFontSize(18)
        } else {
            _ = resetPreviewFontSize()
        }
    }

    @discardableResult
    func zoomPreviewFontIn() -> Bool {
        adjustPreviewFontSize(by: FilePreviewInteraction.zoomStep)
    }

    @discardableResult
    func zoomPreviewFontOut() -> Bool {
        adjustPreviewFontSize(by: 1 / FilePreviewInteraction.zoomStep)
    }

    @discardableResult
    func resetPreviewFontSize() -> Bool {
        setPreviewFontSize(Self.defaultPreviewFontSize)
    }

    @discardableResult
    private func adjustPreviewFontSize(by factor: CGFloat) -> Bool {
        setPreviewFontSize(previewFontSize * factor)
    }

    @discardableResult
    private func setPreviewFontSize(_ nextFontSize: CGFloat) -> Bool {
        let clamped = min(max(nextFontSize, Self.minimumPreviewFontSize), Self.maximumPreviewFontSize)
        guard clamped.isFinite else { return false }
        guard abs(clamped - previewFontSize) > 0.0001 else { return false }
        previewFontSize = clamped
        applyCurrentPreviewFont()
        return true
    }

    func applyCurrentPreviewFont() {
        let nextFont = GlobalFontMagnification.monospacedSystemFont(ofSize: previewFontSize, weight: .regular)
        font = nextFont
        typingAttributes[.font] = nextFont
        // Every zoom path (pinch, modifier-scroll, smart zoom, keyboard shortcut, app-wide
        // magnification) funnels through here, so keeping the ruler in step needs exactly
        // one line rather than one per entry point. Reached through the scroll view so
        // `SavingTextView` gains no stored property.
        (enclosingScrollView?.verticalRulerView as? FilePreviewLineNumberRulerView)?
            .adoptFont(nextFont)
    }

    private func clearPendingShortcutChordPrefixes() {
        pendingEditorShortcutChordPrefix = nil
    }

    private func handleEditorShortcut(_ event: NSEvent) -> Bool {
        if hasMarkedText(),
           shortcutRoutingShouldBypassForPrintableOptionText(event: event) {
            clearPendingShortcutChordPrefixes()
            return false
        }

        let candidates = editorShortcutCandidates()
        if let pendingPrefix = pendingEditorShortcutChordPrefix {
            pendingEditorShortcutChordPrefix = nil
            for candidate in candidates {
                guard candidate.shortcut.firstStroke == pendingPrefix,
                      let secondStroke = candidate.shortcut.secondStroke,
                      secondStroke.matches(event: event) else { continue }
                guard candidate.isAllowed(event) else { return false }
                candidate.perform()
                return true
            }
            return false
        }

        for candidate in candidates {
            let shortcut = candidate.shortcut
            if shortcut.secondStroke != nil {
                if shortcut.firstStroke.matches(event: event) {
                    guard candidate.isAllowed(event) else { return false }
                    pendingEditorShortcutChordPrefix = shortcut.firstStroke
                    return true
                }
                continue
            }
            if shortcut.matches(event: event) {
                guard candidate.isAllowed(event) else { return false }
                candidate.perform()
                return true
            }
        }
        return false
    }

    private func editorShortcutCandidates() -> [
        (shortcut: StoredShortcut, isAllowed: (NSEvent) -> Bool, perform: () -> Void)
    ] {
        var candidates: [(shortcut: StoredShortcut, isAllowed: (NSEvent) -> Bool, perform: () -> Void)] = []
        let saveShortcut = KeyboardShortcutSettings.shortcut(for: .saveFilePreview)
        if !saveShortcut.isUnbound {
            candidates.append((saveShortcut, { _ in true }, { [weak self] in self?.panel?.saveTextContent() }))
        }
        for action in Self.previewFontZoomShortcutActions {
            let shortcut = KeyboardShortcutSettings.shortcut(for: action)
            guard !shortcut.isUnbound else { continue }
            candidates.append((
                shortcut,
                { [weak self] event in
                    self?.previewFontZoomShortcutWhenClauseAllows(action: action, event: event) ?? false
                },
                { [weak self] in self?.performPreviewFontZoomShortcutAction(action) }
            ))
        }
        return candidates
    }

    private func previewFontZoomShortcutWhenClauseAllows(
        action: KeyboardShortcutSettings.Action,
        event: NSEvent
    ) -> Bool {
        if window != nil, let appDelegate = AppDelegate.shared {
            return appDelegate.shortcutWhenClauseAllows(action: action, event: event)
        }
        return KeyboardShortcutSettings.effectiveWhenClause(for: action)
            .evaluate(Self.filePreviewTextEditorShortcutContext)
    }

    private static var filePreviewTextEditorShortcutContext: ShortcutContext {
        ShortcutFocusState(
            browser: false,
            markdown: false,
            sidebar: false,
            filePreviewTextEditor: true
        ).context
    }

    private func performPreviewFontZoomShortcutAction(_ action: KeyboardShortcutSettings.Action) {
        switch action {
        case .browserZoomIn:
            _ = zoomPreviewFontIn()
        case .browserZoomOut:
            _ = zoomPreviewFontOut()
        case .browserZoomReset:
            _ = resetPreviewFontSize()
        default:
            break
        }
    }
}

extension FilePreviewPanel {
    func attachTextView(_ textView: NSTextView) {
        self.textView = textView
        focusCoordinator.register(root: textView, primaryResponder: textView, intent: .textEditor)
    }

    @discardableResult
    func zoomTextPreviewIn() -> Bool {
        guard previewMode == .text,
              let textView = textView as? SavingTextView else { return false }
        return textView.zoomPreviewFontIn()
    }

    @discardableResult
    func zoomTextPreviewOut() -> Bool {
        guard previewMode == .text,
              let textView = textView as? SavingTextView else { return false }
        return textView.zoomPreviewFontOut()
    }

    @discardableResult
    func resetTextPreviewZoom() -> Bool {
        guard previewMode == .text,
              let textView = textView as? SavingTextView else { return false }
        return textView.resetPreviewFontSize()
    }
}
