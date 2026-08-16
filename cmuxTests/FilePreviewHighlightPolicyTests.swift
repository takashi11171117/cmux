import Foundation
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

@Suite("FilePreviewHighlightPolicy")
struct FilePreviewHighlightPolicyTests {
    /// The 13 languages FR-02 requires, with one representative extension each.
    private static let requiredLanguages: [String: String] = [
        "swift": "swift",
        "ts": "typescript",
        "js": "javascript",
        "dart": "dart",
        "php": "php",
        "py": "python",
        "json": "json",
        "yaml": "yaml",
        "md": "markdown",
        "c": "c",
        "cpp": "cpp",
        "rs": "rust",
        "go": "go",
    ]

    @Test("every FR-02 language resolves")
    func requiredLanguageResolves() {
        let policy = FilePreviewHighlightPolicy()
        for (ext, language) in Self.requiredLanguages {
            let decision = policy.decision(path: "/tmp/sample.\(ext)", byteCount: 1_024)
            #expect(
                decision == .highlight(language: language),
                "\(ext) should resolve to \(language), got \(decision)"
            )
        }
    }

    @Test("unknown extension skips without a language")
    func unknownExtensionSkips() {
        let policy = FilePreviewHighlightPolicy()
        #expect(policy.decision(path: "/tmp/sample.foo", byteCount: 1_024) == .skippedNoLanguage)
    }

    @Test("missing extension skips without a language")
    func missingExtensionSkips() {
        let policy = FilePreviewHighlightPolicy()
        #expect(policy.decision(path: "/tmp/LICENSE", byteCount: 1_024) == .skippedNoLanguage)
        #expect(policy.decision(path: "/tmp/.gitignore", byteCount: 1_024) == .skippedNoLanguage)
    }

    @Test("grammars absent from the bundled engine are not offered")
    func absentGrammarsSkip() {
        // AFIDE-01 measured that the bundled highlight.js 11.10.0 has no clojure,
        // elixir, fsharp, gradle, groovy, or scala grammar. Offering a language id the
        // engine cannot honor would cost a round-trip that can only return plain text.
        let policy = FilePreviewHighlightPolicy()
        for ext in ["clj", "cljs", "ex", "exs", "fs", "fsx", "gradle", "groovy", "scala"] {
            #expect(
                policy.decision(path: "/tmp/sample.\(ext)", byteCount: 1_024) == .skippedNoLanguage,
                "\(ext) should not resolve to a grammar the engine lacks"
            )
        }
    }

    @Test("documents past the budget skip")
    func oversizedDocumentSkips() {
        let policy = FilePreviewHighlightPolicy(maximumHighlightBytes: 100)
        #expect(policy.decision(path: "/tmp/sample.swift", byteCount: 101) == .skippedForSize)
        #expect(policy.decision(path: "/tmp/sample.swift", byteCount: 100) == .highlight(language: "swift"))
    }

    @Test("size is decided before language")
    func sizeOutranksLanguage() {
        // An oversized document reports .skippedForSize even when the extension is also
        // unknown, so the reason surfaced is the one that made the work unnecessary.
        let policy = FilePreviewHighlightPolicy(maximumHighlightBytes: 10)
        #expect(policy.decision(path: "/tmp/sample.foo", byteCount: 999) == .skippedForSize)
    }

    @Test("decision ignores file content")
    func decisionIgnoresContent() throws {
        // FR-02 AC3: extension only, never sniffing. Two files with identical names in
        // different directories and wildly different sizes still agree on language.
        let policy = FilePreviewHighlightPolicy()
        let swiftLike = policy.decision(path: "/a/deep/path/Thing.swift", byteCount: 1)
        let other = policy.decision(path: "/b/Thing.swift", byteCount: 900_000)
        #expect(swiftLike == other)
        #expect(swiftLike == .highlight(language: "swift"))
    }

    @Test("extension casing does not matter")
    func extensionCasingIgnored() {
        let policy = FilePreviewHighlightPolicy()
        #expect(policy.decision(path: "/tmp/Sample.SWIFT", byteCount: 1) == .highlight(language: "swift"))
        #expect(policy.decision(path: "/tmp/Sample.Md", byteCount: 1) == .highlight(language: "markdown"))
    }

    @Test("language table is injectable")
    func injectedTableIsUsed() {
        let policy = FilePreviewHighlightPolicy(
            languages: FilePreviewSyntaxLanguage(languagesByExtension: ["zz": "zzlang"])
        )
        #expect(policy.decision(path: "/tmp/a.zz", byteCount: 1) == .highlight(language: "zzlang"))
        #expect(policy.decision(path: "/tmp/a.swift", byteCount: 1) == .skippedNoLanguage)
    }
}
