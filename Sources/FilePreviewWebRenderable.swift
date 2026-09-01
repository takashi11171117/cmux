import Foundation

/// Which file extensions have a rendered form worth offering alongside the source view.
///
/// A tiny value type on purpose. Deciding by extension keeps the source-view path (the plain
/// text editor) as the default, and the "Open Rendered" affordance appears only when there
/// is actually another way to look at the file. Split from ``FilePreviewPanel`` so the
/// button predicate is testable without touching the panel.
enum FilePreviewWebRenderable {
    /// Extensions whose file rendered form the code-review column can host in a WebView.
    ///
    /// - `html` / `htm`: standard web page.
    /// - `svg`: inline SVG document, rendered as a picture by WebKit.
    static let extensions: Set<String> = ["html", "htm", "svg"]

    /// Whether a file has a rendered form worth an "Open Rendered" button.
    ///
    /// - Parameter fileURL: The file backing the current preview.
    /// - Returns: `true` when the extension is web-renderable.
    static func canRender(fileURL: URL) -> Bool {
        extensions.contains(fileURL.pathExtension.lowercased())
    }
}
