import Foundation

extension TerminalSurface {
    /// Copies the current selection with its line breaks removed.
    ///
    /// The view does the joining (it owns the Ghostty selection and the clipboard);
    /// the surface only routes the request so the keyboard shortcut, the command
    /// palette, and the dock all reach the same code as the context menu item.
    ///
    /// - Returns: Whether the view copied something. `false` when there is no
    ///   selection or it contains only whitespace.
    @discardableResult
    @MainActor
    public func copySelectionAsSingleLine() -> Bool {
        surfaceView.copySelectionAsSingleLine()
    }
}
