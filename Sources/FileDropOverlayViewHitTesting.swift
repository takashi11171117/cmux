import AppKit
import Bonsplit
import Foundation
import WebKit

extension FileDropOverlayView {
    func updateDragTarget(_ sender: any NSDraggingInfo, phase: String) -> NSDragOperation {
        let loc = sender.draggingLocation
        let hasLocalDraggingSource = sender.draggingSource != nil
        let types = sender.draggingPasteboard.types
        let shouldCapture = DragOverlayRoutingPolicy.shouldCaptureFileDropDestination(
            pasteboardTypes: types,
            hasLocalDraggingSource: hasLocalDraggingSource
        )
        updateHintBadge(sender: sender, pasteboardTypes: types)

        if shouldRouteFileDropToTextDestination(sender) {
            let paneDropTarget = paneDropTargetForTextDrop(at: loc)
            if let prev = activePaneDropTarget {
                if fileDropPaneTargetsAreIdentical(prev, paneDropTarget) {
                    return prev.fileDropDraggingUpdated(sender)
                }
                prev.fileDropDraggingExited(sender)
                activePaneDropTarget = nil
            }
            if let paneDropTarget {
                if let prev = activeDragWebView {
                    prev.draggingExited(sender)
                    activeDragWebView = nil
                }
                activePaneDropTarget = paneDropTarget
                return paneDropTarget.fileDropDraggingEntered(sender)
            }
            if let webView = webViewUnderPoint(loc) {
                if activeDragWebView !== webView {
                    if let prev = activeDragWebView {
                        prev.draggingExited(sender)
                    }
                    activeDragWebView = webView
                    return webView.draggingEntered(sender)
                }
                return webView.draggingUpdated(sender)
            }
            if let prev = activeDragWebView {
                prev.draggingExited(sender)
                activeDragWebView = nil
            }
            return textDropDestinationKindUnderPoint(loc) == nil
                ? []
                : DragOverlayRoutingPolicy.textDropOperation(pasteboardTypes: types)
        }

        let paneDropTarget = shouldCapture ? paneDropTargetUnderPoint(loc) : nil
        let webView = shouldCapture && paneDropTarget == nil ? webViewUnderPoint(loc) : nil

        if let prev = activeDragWebView {
            if prev !== webView {
                prev.draggingExited(sender)
                activeDragWebView = nil
            }
        }
        if let prev = activePaneDropTarget,
           !fileDropPaneTargetsAreIdentical(prev, paneDropTarget) {
            prev.fileDropDraggingExited(sender)
            activePaneDropTarget = nil
        }

        if let paneDropTarget {
            if !fileDropPaneTargetsAreIdentical(activePaneDropTarget, paneDropTarget) {
                activePaneDropTarget = paneDropTarget
                return paneDropTarget.fileDropDraggingEntered(sender)
            }
            return paneDropTarget.fileDropDraggingUpdated(sender)
        }

        if let webView {
            if activeDragWebView !== webView {
                activeDragWebView = webView
                return webView.draggingEntered(sender)
            }
            return webView.draggingUpdated(sender)
        }

        let hasPaneTarget = terminalUnderPoint(loc) != nil
#if DEBUG
        logDragRouteDecision(
            phase: phase,
            pasteboardTypes: types,
            shouldCapture: shouldCapture,
            hasLocalDraggingSource: hasLocalDraggingSource,
            hasPaneTarget: hasPaneTarget
        )
#endif
        guard shouldCapture, hasPaneTarget else { return [] }
        return .copy
    }

    private func fileDropPaneTargetsAreIdentical(
        _ lhs: (any FileDropPaneTarget)?,
        _ rhs: (any FileDropPaneTarget)?
    ) -> Bool {
        guard let lhs, let rhs else { return lhs == nil && rhs == nil }
        return (lhs as AnyObject) === (rhs as AnyObject)
    }

    private func debugPasteboardTypes(_ types: [NSPasteboard.PasteboardType]?) -> String {
        guard let types, !types.isEmpty else { return "-" }
        return types.map(\.rawValue).joined(separator: ",")
    }

    func shouldRouteFileDropToTextDestination(_ sender: any NSDraggingInfo) -> Bool {
        let canDropAsText = textDropDestinationKindUnderPoint(sender.draggingLocation) != nil
        return DragOverlayRoutingPolicy.shouldRouteFileDropToTextDestination(
            pasteboardTypes: sender.draggingPasteboard.types,
            modifierFlags: DragOverlayRoutingPolicy.currentModifierFlags,
            canDropAsText: canDropAsText
        )
    }

    private func updateHintBadge(
        sender: any NSDraggingInfo,
        pasteboardTypes: [NSPasteboard.PasteboardType]?
    ) {
        let windowPoint = sender.draggingLocation
        if editableTextViewUnderPoint(windowPoint) == nil,
           webViewUnderPoint(windowPoint) != nil {
            guard DragOverlayRoutingPolicy.hasFileURL(pasteboardTypes),
                  !DragOverlayRoutingPolicy.currentModifierFlags.contains(.shift),
                  let hintText = FileDropTextDestinationKind.editor.hintText(for: .preview),
                  let targetBounds = hintBadgeTargetBoundsUnderPoint(windowPoint) else {
                hintBadgeView.hide()
                return
            }
            hintBadgeView.show(text: hintText, centeredIn: targetBounds, clippedTo: bounds)
            return
        }

        let kind = textDropDestinationKindUnderPoint(windowPoint)
        guard let alternateBehavior = DragOverlayRoutingPolicy.alternateFileDropBehaviorForShiftHint(
            pasteboardTypes: pasteboardTypes,
            modifierFlags: DragOverlayRoutingPolicy.currentModifierFlags,
            canDropAsText: kind != nil
        ), let kind,
           let hintText = kind.hintText(for: alternateBehavior),
           let targetBounds = hintBadgeTargetBoundsUnderPoint(windowPoint) else {
            hintBadgeView.hide()
            return
        }
        hintBadgeView.show(text: hintText, centeredIn: targetBounds, clippedTo: bounds)
    }

    func textDropDestinationKindUnderPoint(_ windowPoint: NSPoint) -> FileDropTextDestinationKind? {
        if editableTextViewUnderPoint(windowPoint) != nil {
            return .editor
        }
        if webViewUnderPoint(windowPoint) != nil {
            return .editor
        }
        if terminalUnderPoint(windowPoint) != nil {
            return .terminal
        }
        return nil
    }

    private func hintBadgeTargetBoundsUnderPoint(_ windowPoint: NSPoint) -> CGRect? {
        if let paneDropTarget = paneDropTargetUnderPoint(windowPoint),
           let targetView = paneDropTarget as? NSView {
            return convert(targetView.bounds, from: targetView)
        }
        if let terminal = terminalUnderPoint(windowPoint) {
            return convert(terminal.bounds, from: terminal)
        }
        if let webView = webViewUnderPoint(windowPoint) {
            return convert(webView.bounds, from: webView)
        }
        if let textView = editableTextViewUnderPoint(windowPoint) {
            return convert(textView.visibleRect, from: textView)
        }
        return nil
    }

    func performFileDropAsText(_ sender: any NSDraggingInfo) -> Bool {
        let urls = DragOverlayRoutingPolicy.fileURLs(from: sender.draggingPasteboard)
        guard !urls.isEmpty else { return false }

        let windowPoint = sender.draggingLocation
        if let textView = editableTextViewUnderPoint(windowPoint) {
            let text = TerminalImageTransferPlanner.insertedText(forFileURLs: urls)
            guard !text.isEmpty else { return false }
            return insert(text, into: textView)
        }
        if let terminal = terminalUnderPoint(windowPoint) {
            return insert(urls, into: terminal)
        }
        return false
    }

    private func viewUnderPoint(_ windowPoint: NSPoint) -> NSView? {
        guard let window, let contentView = window.contentView else { return nil }
        isHidden = true
        defer { isHidden = false }
        let point = contentView.convert(windowPoint, from: nil)
        return contentView.hitTest(point)
    }

    private func editableTextViewUnderPoint(_ windowPoint: NSPoint) -> NSTextView? {
        var current = viewUnderPoint(windowPoint)
        while let view = current {
            if let textView = view as? NSTextView, textView.isEditable {
                return textView
            }
            if let textField = view as? NSTextField,
               textField.isEditable,
               let editor = textField.currentEditor() as? NSTextView {
                return editor
            }
            current = view.superview
        }

        return nil
    }

    private func insert(_ text: String, into textView: NSTextView) -> Bool {
        guard textView.isEditable else { return false }
        textView.window?.makeFirstResponder(textView)
        textView.insertText(text, replacementRange: textView.selectedRange())
        return true
    }

    private func insert(_ urls: [URL], into terminal: GhosttyNSView) -> Bool {
        FileDropTextDropController.performTerminalFileDrop(
            terminal: terminal,
            urls: urls
        )
    }

    /// Hit-tests the window to find a WKWebView (browser panel) under the cursor.
    func webViewUnderPoint(_ windowPoint: NSPoint) -> WKWebView? {
        if let window,
           let portalWebView = BrowserWindowPortalRegistry.webViewAtWindowPoint(windowPoint, in: window) {
            return portalWebView
        }

        guard let window, let contentView = window.contentView else { return nil }
        isHidden = true
        defer { isHidden = false }
        let point = contentView.convert(windowPoint, from: nil)
        let hitView = contentView.hitTest(point)

        var current: NSView? = hitView
        while let view = current {
            if let webView = view as? WKWebView { return webView }
            current = view.superview
        }
        return nil
    }

    private func debugTopHitViewForCurrentEvent() -> String {
        guard let window,
              let currentEvent = NSApp.currentEvent,
              let contentView = window.contentView,
              let themeFrame = contentView.superview else { return "-" }

        let pointInTheme = themeFrame.convert(currentEvent.locationInWindow, from: nil)
        // Don't toggle isHidden here — it triggers setNeedsDisplay which can
        // exceed AppKit's display-pass limit during cursor-update display cycles.
        guard let hit = themeFrame.hitTest(pointInTheme) else { return "nil" }
        var chain: [String] = []
        var current: NSView? = hit
        var depth = 0
        while let view = current, depth < 6 {
            chain.append(debugHitViewDescriptor(view))
            current = view.superview
            depth += 1
        }
        return chain.joined(separator: "->")
    }

    private func debugHitViewDescriptor(_ view: NSView) -> String {
        let className = String(describing: type(of: view))
        let ptr = String(describing: Unmanaged.passUnretained(view).toOpaque())
        let dragTypes = debugRegisteredDragTypes(view)
        return "\(className)@\(ptr){dragTypes=\(dragTypes)}"
    }

    private func debugRegisteredDragTypes(_ view: NSView) -> String {
        let types = view.registeredDraggedTypes
        guard !types.isEmpty else { return "-" }

        let interestingTypes = types.filter { type in
            let raw = type.rawValue
            return PasteboardFileURLReader.fileURLPasteboardTypes.contains(type)
                || raw == DragOverlayRoutingPolicy.bonsplitTabTransferType.rawValue
                || raw == DragOverlayRoutingPolicy.sidebarTabReorderType.rawValue
                || raw.contains("public.text")
                || raw.contains("public.url")
                || raw.contains("public.data")
        }
        let selected = interestingTypes.isEmpty ? Array(types.prefix(3)) : interestingTypes
        let rendered = selected.map(\.rawValue).joined(separator: ",")
        if selected.count < types.count {
            return "\(rendered),+\(types.count - selected.count)"
        }
        return rendered
    }

    private func hasRelevantDragTypes(_ types: [NSPasteboard.PasteboardType]?) -> Bool {
        guard let types else { return false }
        return DragOverlayRoutingPolicy.hasFileDropPayload(types)
            || types.contains(DragOverlayRoutingPolicy.bonsplitTabTransferType)
            || types.contains(DragOverlayRoutingPolicy.sidebarTabReorderType)
    }

    private func debugEventName(_ eventType: NSEvent.EventType?) -> String {
        guard let eventType else { return "none" }
        switch eventType {
        case .cursorUpdate: return "cursorUpdate"
        case .appKitDefined: return "appKitDefined"
        case .systemDefined: return "systemDefined"
        case .applicationDefined: return "applicationDefined"
        case .periodic: return "periodic"
        case .mouseMoved: return "mouseMoved"
        case .mouseEntered: return "mouseEntered"
        case .mouseExited: return "mouseExited"
        case .flagsChanged: return "flagsChanged"
        case .leftMouseDown: return "leftMouseDown"
        case .leftMouseUp: return "leftMouseUp"
        case .leftMouseDragged: return "leftMouseDragged"
        case .rightMouseDown: return "rightMouseDown"
        case .rightMouseUp: return "rightMouseUp"
        case .rightMouseDragged: return "rightMouseDragged"
        case .otherMouseDown: return "otherMouseDown"
        case .otherMouseUp: return "otherMouseUp"
        case .otherMouseDragged: return "otherMouseDragged"
        case .scrollWheel: return "scrollWheel"
        default: return "other(\(eventType.rawValue))"
        }
    }

#if DEBUG
    func logHitTestDecision(
        pasteboardTypes: [NSPasteboard.PasteboardType]?,
        eventType: NSEvent.EventType?,
        shouldCapture: Bool
    ) {
        let isDragEvent = eventType == .leftMouseDragged
            || eventType == .rightMouseDragged
            || eventType == .otherMouseDragged
        guard shouldCapture || isDragEvent || hasRelevantDragTypes(pasteboardTypes) else { return }

        let signature = "\(shouldCapture ? 1 : 0)|\(debugEventName(eventType))|\(debugPasteboardTypes(pasteboardTypes))"
        guard lastHitTestLogSignature != signature else { return }
        lastHitTestLogSignature = signature
        cmuxDebugLog(
            "overlay.fileDrop.hitTest capture=\(shouldCapture ? 1 : 0) " +
            "event=\(debugEventName(eventType)) " +
            "topHit=\(debugTopHitViewForCurrentEvent()) " +
            "types=\(debugPasteboardTypes(pasteboardTypes))"
        )
    }

    func logDragRouteDecision(
        phase: String,
        pasteboardTypes: [NSPasteboard.PasteboardType]?,
        shouldCapture: Bool,
        hasLocalDraggingSource: Bool,
        hasPaneTarget: Bool
    ) {
        guard shouldCapture || hasRelevantDragTypes(pasteboardTypes) else { return }
        let signature = [
            shouldCapture ? "1" : "0",
            hasLocalDraggingSource ? "1" : "0",
            hasPaneTarget ? "1" : "0",
            debugPasteboardTypes(pasteboardTypes)
        ].joined(separator: "|")
        guard lastDragRouteLogSignatureByPhase[phase] != signature else { return }
        lastDragRouteLogSignatureByPhase[phase] = signature
        cmuxDebugLog(
            "overlay.fileDrop.\(phase) capture=\(shouldCapture ? 1 : 0) " +
            "localSource=\(hasLocalDraggingSource ? 1 : 0) " +
            "hasPane=\(hasPaneTarget ? 1 : 0) " +
            "types=\(debugPasteboardTypes(pasteboardTypes))"
        )
    }
#endif
    /// Hit-tests the window to find the GhosttyNSView under the cursor.
    func terminalUnderPoint(_ windowPoint: NSPoint) -> GhosttyNSView? {
        if let window,
           let portalTerminal = TerminalWindowPortalRegistry.terminalViewAtWindowPoint(windowPoint, in: window) {
            return portalTerminal
        }

        guard let window, let contentView = window.contentView else { return nil }
        isHidden = true
        defer { isHidden = false }
        let point = contentView.convert(windowPoint, from: nil)
        let hitView = contentView.hitTest(point)

        var current: NSView? = hitView
        while let view = current {
            if let terminal = view as? GhosttyNSView { return terminal }
            current = view.superview
        }
        return nil
    }

    func shouldDeferFileDropOverlayToBonsplitTabBar(at point: NSPoint) -> Bool {
        guard let window else { return false }
        let windowPoint = convert(point, to: nil)
        return BonsplitTabBarHitRegionRegistry.containsWindowPoint(windowPoint, in: window)
    }

    /// Whether the drag is over the file-explorer outline, in which case the overlay
    /// should let the drop reach the outline instead of intercepting it.
    ///
    /// `point` is in this overlay's local coordinate space. `hitTest` calls it that way,
    /// so it needs a local-space entry point. Internally it converts to the window
    /// coordinate space, which is what the shared implementation needs.
    func shouldDeferFileDropOverlayToFileExplorer(at point: NSPoint) -> Bool {
        let windowPoint = convert(point, to: nil)
        return isFileExplorerOutlineAtWindowPoint(windowPoint)
    }

    /// Returns the drag operation to advertise while forwarding a file-explorer drop.
    ///
    /// - When the drag is over the outline, this method resolves the target outline,
    ///   caches it in ``activeFileExplorerOutline``, and returns `.copy` (or `.move` when
    ///   the Option modifier is held).
    /// - When the drag leaves the outline (or was never over it), the cache clears and
    ///   the method returns nil so the normal drag routing takes over.
    ///
    /// This is what actually lets Finder drops land in the Files tree: the overlay owns
    /// the AppKit drag destination for the whole window, so it accepts the drop on the
    /// outline's behalf and hands it off in ``performFileExplorerFileDrop(sender:outline:)``.
    func forwardedFileExplorerDragOperation(_ sender: any NSDraggingInfo) -> NSDragOperation? {
        // Only file URLs are eligible — other pasteboard types have their own routing.
        guard sender.draggingPasteboard.canReadObject(forClasses: [NSURL.self], options: nil) else {
            activeFileExplorerOutline = nil
            return nil
        }
        guard let outline = fileExplorerOutlineAtWindowPoint(sender.draggingLocation) else {
            activeFileExplorerOutline = nil
            return nil
        }
        activeFileExplorerOutline = outline
        let modifiers = NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask)
        return modifiers.contains(.option) ? .move : .copy
    }

    /// Runs the file drop, using the outline's row under the cursor to pick the folder.
    ///
    /// Mirrors the Files coordinator's drop rules: drop on a directory row means "into
    /// that directory", drop on a file row means "into that file's parent", drop on
    /// empty space means "into the workspace root". Same uniquification (`foo 2.txt`)
    /// as the context-menu Duplicate action.
    func performFileExplorerFileDrop(
        sender: any NSDraggingInfo,
        outline: FileExplorerNSOutlineView
    ) -> Bool {
        guard let urls = sender.draggingPasteboard.readObjects(
            forClasses: [NSURL.self], options: nil
        ) as? [URL], !urls.isEmpty else { return false }

        let target = fileExplorerDropTargetDirectory(sender: sender, outline: outline)
        guard let target else { return false }

        let modifiers = NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let move = modifiers.contains(.option)
        do {
            for source in urls {
                if move {
                    _ = try FileExplorerFileOperation.moveInto(source, directory: target)
                } else {
                    _ = try FileExplorerFileOperation.copyInto(source, directory: target)
                }
            }
            outline.fileExplorerCoordinator?.store.reload()
            return true
        } catch {
            FileExplorerNamePrompt.presentFailure(error, window: outline.window)
            return false
        }
    }

    /// Resolves the destination directory for a forwarded drop.
    private func fileExplorerDropTargetDirectory(
        sender: any NSDraggingInfo,
        outline: FileExplorerNSOutlineView
    ) -> URL? {
        // Convert the window-space location to the outline's own coordinate space so
        // `row(at:)` can find the row under the cursor.
        let outlinePoint = outline.convert(sender.draggingLocation, from: nil)
        let row = outline.row(at: outlinePoint)
        if row >= 0, let node = outline.item(atRow: row) as? FileExplorerNode {
            if node.isDirectory {
                return URL(fileURLWithPath: node.path)
            }
            return URL(fileURLWithPath: node.path).deletingLastPathComponent()
        }
        // No row under the cursor — drop into the workspace root.
        guard let store = outline.fileExplorerCoordinator?.store,
              !store.rootPath.isEmpty else { return nil }
        return URL(fileURLWithPath: store.rootPath)
    }

    /// The `FileExplorerNSOutlineView` under a window-space point, if any.
    private func fileExplorerOutlineAtWindowPoint(_ windowPoint: NSPoint) -> FileExplorerNSOutlineView? {
        guard let window, let contentView = window.contentView else { return nil }
        isHidden = true
        defer { isHidden = false }
        let contentPoint = contentView.convert(windowPoint, from: nil)
        var view = contentView.hitTest(contentPoint)
        while let current = view {
            if let outline = current as? FileExplorerNSOutlineView { return outline }
            view = current.superview
        }
        return nil
    }

    /// Whether a point in window coordinates lies over the file-explorer outline.
    ///
    /// Split from the local-space entry point so drag callbacks can use it — those
    /// receive `sender.draggingLocation`, which is already in window coordinates. Same
    /// shape as ``shouldDeferFileDropOverlayToBonsplitTabBar(at:)``: hide self,
    /// hit-test through the window's content view, walk up the responder chain looking
    /// for a `FileExplorerNSOutlineView`. Its own registered drag types (`.fileURL`)
    /// then receive the drag.
    func isFileExplorerOutlineAtWindowPoint(_ windowPoint: NSPoint) -> Bool {
        guard let window, let contentView = window.contentView else { return false }
        isHidden = true
        defer { isHidden = false }
        let contentPoint = contentView.convert(windowPoint, from: nil)
        var view = contentView.hitTest(contentPoint)
        while let current = view {
            if current is FileExplorerNSOutlineView { return true }
            view = current.superview
        }
        return false
    }

    func paneDropTargetUnderPoint(_ windowPoint: NSPoint) -> (any FileDropPaneTarget)? {
        if let paneTarget = inlinePaneDropTargetUnderPoint(windowPoint) {
            return paneTarget
        }
        guard let window else { return nil }
        if let terminalPaneTarget = TerminalWindowPortalRegistry.terminalPaneDropTargetAtWindowPoint(windowPoint, in: window) {
            return terminalPaneTarget
        }
        return BrowserWindowPortalRegistry.browserPaneDropTargetAtWindowPoint(windowPoint, in: window)
    }

    func paneDropTargetForTextDrop(at windowPoint: NSPoint) -> (any FileDropPaneTarget)? {
        if let textView = editableTextViewUnderPoint(windowPoint),
           !(textView is SavingTextView) {
            return nil
        }
        return paneDropTargetUnderPoint(windowPoint)
    }

    private func inlinePaneDropTargetUnderPoint(_ windowPoint: NSPoint) -> PaneDropTargetView? {
        guard let window, let contentView = window.contentView else { return nil }
        isHidden = true
        defer { isHidden = false }

        let point = contentView.convert(windowPoint, from: nil)
        return paneDropTarget(in: contentView, at: point)
    }

    private func paneDropTarget(in view: NSView, at point: NSPoint) -> PaneDropTargetView? {
        for subview in view.subviews.reversed() {
            guard !subview.isHidden, subview.alphaValue > 0 else { continue }
            let pointInSubview = subview.convert(point, from: view)
            guard subview.bounds.contains(pointInSubview) else { continue }
            if let paneTarget = subview as? PaneDropTargetView {
                return paneTarget
            }
            if let nestedTarget = paneDropTarget(in: subview, at: pointInSubview) {
                return nestedTarget
            }
        }
        return view as? PaneDropTargetView
    }
}
