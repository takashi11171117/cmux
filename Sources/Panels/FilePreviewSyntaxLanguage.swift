import Foundation

/// Resolves a file path to the engine's language identifier, by extension only.
///
/// Instantiated with a table so tests can inject their own; the default table is
/// ``bundledHighlightJSLanguages``, which is scoped to the grammars actually present
/// in the bundled highlight.js build.
///
/// ```swift
/// let languages = FilePreviewSyntaxLanguage()
/// languages.language(forPath: "/tmp/Main.swift")  // "swift"
/// languages.language(forPath: "/tmp/notes.foo")   // nil
/// ```
struct FilePreviewSyntaxLanguage: Sendable {
    private let languagesByExtension: [String: String]

    /// Creates a resolver over `languagesByExtension`, defaulting to the bundled table.
    ///
    /// - Parameter languagesByExtension: Lowercased extension to engine language id.
    init(languagesByExtension: [String: String] = FilePreviewSyntaxLanguage.bundledHighlightJSLanguages) {
        self.languagesByExtension = languagesByExtension
    }

    /// Returns the language id for `path`, or `nil` when the extension is unknown.
    ///
    /// Decided purely from the path extension. Content is never inspected: the same
    /// extension always yields the same answer regardless of what the file contains.
    /// (`FilePreviewKindResolver.sniffLooksLikeText` sniffs content, but it answers
    /// "is this text at all", which is a different question.)
    ///
    /// - Parameter path: Filesystem path; only its extension is read.
    /// - Returns: Engine language id, or `nil` to fall back to plain text.
    func language(forPath path: String) -> String? {
        let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
        guard !ext.isEmpty else { return nil }
        return languagesByExtension[ext]
    }

    /// Extension-to-language table restricted to grammars the bundled engine has.
    ///
    /// Derived from `ChatArtifactSyntaxHighlightPolicy.languagesByExtension` on the iOS
    /// side, then trimmed: the bundled `Resources/markdown-viewer/highlight.min.js`
    /// (11.10.0) registers 36 languages, and AFIDE-01 measured that `clojure`,
    /// `elixir`, `fsharp`, `gradle`, `groovy`, and `scala` are **not** among them.
    /// Keeping those rows would return a language id for which the engine produces no
    /// tokens — an engine round-trip that can only ever yield plain text.
    ///
    /// `dart` is also absent from that build, but unlike the six above it is required by
    /// FR-02, so the matching 11.10.0 grammar is vendored next to the core script and
    /// loaded by ``FilePreviewHighlightJavaScriptEngine/additionalGrammars``.
    ///
    /// The table is duplicated rather than shared: the macOS app does not link
    /// `Packages/iOS/CmuxAgentChatUI`, and moving that package to `Packages/Shared`
    /// to share one dictionary would rewrite iOS dependencies for no benefit.
    static let bundledHighlightJSLanguages: [String: String] = [
        "bash": "bash",
        "c": "c",
        "cc": "cpp",
        "cjs": "javascript",
        "cpp": "cpp",
        "cs": "csharp",
        "css": "css",
        "cxx": "cpp",
        "dart": "dart",
        "go": "go",
        "h": "c",
        "hh": "cpp",
        "hpp": "cpp",
        "htm": "xml",
        "html": "xml",
        "java": "java",
        "js": "javascript",
        "json": "json",
        "jsx": "javascript",
        "kt": "kotlin",
        "kts": "kotlin",
        "less": "less",
        "lua": "lua",
        "m": "objectivec",
        "markdown": "markdown",
        "md": "markdown",
        "mjs": "javascript",
        "mm": "objectivec",
        "php": "php",
        "pl": "perl",
        "pm": "perl",
        "py": "python",
        "r": "r",
        "rb": "ruby",
        "rs": "rust",
        "sass": "scss",
        "scss": "scss",
        "sh": "bash",
        "sql": "sql",
        "swift": "swift",
        "ts": "typescript",
        "tsx": "typescript",
        "xml": "xml",
        "yaml": "yaml",
        "yml": "yaml",
        "zsh": "bash",
    ]
}
