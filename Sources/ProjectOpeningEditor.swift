import Foundation

/// Whether an application takes a folder as the project a file belongs to.
///
/// Every editor in the VS Code family — VS Code itself, Cursor, VSCodium, and the other forks —
/// carries `Contents/Resources/app/product.json` inside its own bundle. Detecting the family by
/// that file rather than by a list of bundle identifiers means a fork nobody here has heard of
/// still works, and an editor that merely opens the file type is not handed a directory it has
/// no idea what to do with.
///
/// ```swift
/// ProjectOpeningEditor.live.opensFolderAsProject(
///     applicationURL: URL(fileURLWithPath: "/Applications/Visual Studio Code.app")
/// )  // true
/// ```
struct ProjectOpeningEditor: Sendable {
    /// Seam for tests: whether a file exists at a path.
    var fileExistsAtPath: @Sendable (String) -> Bool

    static let live = ProjectOpeningEditor(
        fileExistsAtPath: { FileManager.default.fileExists(atPath: $0) }
    )

    /// Relative path of the marker inside an application bundle.
    static let markerPath = "Contents/Resources/app/product.json"

    /// Whether this application should be handed the project directory alongside the file.
    ///
    /// - Parameter applicationURL: Bundle URL of the application about to be launched.
    func opensFolderAsProject(applicationURL: URL) -> Bool {
        let marker = applicationURL.appendingPathComponent(Self.markerPath, isDirectory: false)
        return fileExistsAtPath(marker.path(percentEncoded: false))
    }
}
