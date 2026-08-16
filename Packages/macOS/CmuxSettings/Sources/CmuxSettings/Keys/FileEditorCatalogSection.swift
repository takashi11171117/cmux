import Foundation

/// Settings under the dotted-id prefix `fileEditor.*`.
///
/// Controls the built-in plain-text file editor (the text preview that the
/// file explorer and `cmux` file routing open for editable text files). This
/// is distinct from the rendered markdown viewer, whose settings live in
/// ``MarkdownCatalogSection``.
public struct FileEditorCatalogSection: SettingCatalogSection {
    /// Whether long lines soft-wrap at the editor's right edge.
    ///
    /// `false` (the default) preserves the established behavior: lines extend
    /// past the viewport and a horizontal scroller appears. `true` wraps each
    /// line to the visible width and hides the horizontal scroller, the way a
    /// prose editor does. Changing this applies live to open editors.
    public let wordWrap = DefaultsKey<Bool>(
        id: "fileEditor.wordWrap",
        defaultValue: false,
        userDefaultsKey: "fileEditor.wordWrap"
    )

    /// Whether source files are colored by syntax.
    ///
    /// `true` (the default) colors keywords, strings, comments, numbers, types, and
    /// attributes using the same palette the markdown viewer uses for fenced code, so a
    /// code file and a code block look alike. Files whose extension maps to no known
    /// grammar, and files past the highlighter's size budget, render as plain text
    /// regardless. Changing this applies live to open editors.
    public let syntaxHighlight = DefaultsKey<Bool>(
        id: "fileEditor.syntaxHighlight",
        defaultValue: true,
        userDefaultsKey: "fileEditor.syntaxHighlight"
    )

    /// Whether a line-number ruler is drawn down the editor's left margin.
    ///
    /// `true` (the default) numbers logical lines: a soft-wrapped line keeps one number
    /// rather than numbering each visual row. The ruler exists only while an editor is
    /// open. Changing this applies live to open editors.
    public let lineNumbers = DefaultsKey<Bool>(
        id: "fileEditor.lineNumbers",
        defaultValue: true,
        userDefaultsKey: "fileEditor.lineNumbers"
    )

    /// Creates the file editor settings section with its default keys.
    public init() {}
}
