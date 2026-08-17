import Foundation
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

/// Covers extension-to-language resolution and the contents of the bundled table.
///
/// The table rows are asserted, not just the lookup logic. A row for a grammar the bundled
/// engine does not register costs a full JavaScript round-trip that can only ever return
/// plain text, and nothing at runtime reports it — the file simply renders unhighlighted.
@Suite("FilePreviewSyntaxLanguage")
struct FilePreviewSyntaxLanguageTests {
    private let languages = FilePreviewSyntaxLanguage()

    // MARK: - Lookup

    @Test("resolves a known extension")
    func resolvesKnownExtension() {
        #expect(languages.language(forPath: "/tmp/Main.swift") == "swift")
    }

    @Test("returns nil for an unknown extension so the caller falls back to plain text")
    func unknownExtensionIsNil() {
        #expect(languages.language(forPath: "/tmp/notes.unknownext") == nil)
    }

    @Test("returns nil when there is no extension at all")
    func noExtensionIsNil() {
        #expect(languages.language(forPath: "/tmp/LICENSE") == nil)
        #expect(languages.language(forPath: "/tmp/Makefile") == nil)
    }

    @Test("matches case-insensitively")
    func matchesUppercaseExtension() {
        #expect(languages.language(forPath: "/tmp/Main.SWIFT") == "swift")
        #expect(languages.language(forPath: "/tmp/Page.HTML") == languages.language(forPath: "/tmp/page.html"))
    }

    @Test("a dotfile with no extension resolves to nil")
    func dotfileIsNil() {
        // URL.pathExtension is empty for ".gitignore", so this must not be read as
        // extension "gitignore".
        #expect(languages.language(forPath: "/tmp/.gitignore") == nil)
    }

    @Test("only the last extension is considered")
    func lastExtensionWins() {
        // "swift" appears earlier in the name but is not the extension.
        #expect(languages.language(forPath: "/tmp/archive.swift.py") == "python")
        // And the reverse: an unknown trailing extension wins over a known earlier one.
        #expect(languages.language(forPath: "/tmp/archive.py.unknownext") == nil)
    }

    @Test("uses the injected table rather than the bundled one")
    func honoursInjectedTable() {
        let custom = FilePreviewSyntaxLanguage(languagesByExtension: ["zz": "zeta"])
        #expect(custom.language(forPath: "/tmp/a.zz") == "zeta")
        #expect(custom.language(forPath: "/tmp/Main.swift") == nil)
    }

    // MARK: - Bundled table contents

    @Test("dart is present, since FR-02 requires it and its grammar is vendored")
    func dartIsPresent() {
        #expect(languages.language(forPath: "/tmp/main.dart") == "dart")
        #expect(FilePreviewSyntaxLanguage.bundledHighlightJSLanguages["dart"] == "dart")
    }

    @Test("dart's grammar is loaded by the engine, not merely listed in the table")
    func dartGrammarIsLoaded() {
        // A row in the table without a matching grammar means every .dart file pays for an
        // engine round-trip and comes back unhighlighted.
        #expect(FilePreviewHighlightJavaScriptEngine.additionalGrammars.contains("dart"))
    }

    @Test("languages absent from the bundled engine are not in the table")
    func absentGrammarsAreExcluded() {
        // AFIDE-01 measured that highlight.js 11.10.0's bundled build does not register
        // these. Re-adding a row here would silently produce unhighlighted output.
        let notInBundledEngine = ["clojure", "elixir", "fsharp", "gradle", "groovy", "scala"]
        let values = Set(FilePreviewSyntaxLanguage.bundledHighlightJSLanguages.values)

        for language in notInBundledEngine {
            #expect(!values.contains(language), "\(language) is not in the bundled engine")
        }
    }

    @Test("every table key is lowercase, or case-insensitive lookup silently misses it")
    func tableKeysAreLowercase() {
        for key in FilePreviewSyntaxLanguage.bundledHighlightJSLanguages.keys {
            #expect(key == key.lowercased(), "\(key) would never match: lookup lowercases first")
        }
    }

    @Test("no table key carries a leading dot")
    func tableKeysHaveNoLeadingDot() {
        // `URL.pathExtension` never includes the dot, so a ".swift" key would be dead weight.
        for key in FilePreviewSyntaxLanguage.bundledHighlightJSLanguages.keys {
            #expect(!key.hasPrefix("."), "\(key) can never match a pathExtension")
        }
    }

    @Test("the common extensions this fork is used on all resolve")
    func commonExtensionsResolve() {
        let expected: [String: String] = [
            "a.swift": "swift",
            "a.ts": "typescript",
            "a.tsx": "typescript",
            "a.js": "javascript",
            "a.py": "python",
            "a.rb": "ruby",
            "a.go": "go",
            "a.rs": "rust",
            "a.json": "json",
            "a.yml": "yaml",
            "a.sh": "bash",
            "a.dart": "dart",
        ]

        for (name, language) in expected {
            #expect(languages.language(forPath: "/tmp/\(name)") == language, "\(name)")
        }
    }
}
