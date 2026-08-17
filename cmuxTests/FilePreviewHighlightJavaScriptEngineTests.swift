import Foundation
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

@Suite("FilePreviewHighlightJavaScriptEngine")
struct FilePreviewHighlightJavaScriptEngineTests {
    /// The checked-in highlight.js, located relative to this source file so the test does
    /// not depend on which bundle is `main` under the test runner.
    /// The checked-in asset directory, where scripts are still plain `.js`.
    private static var sourceDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Resources/markdown-viewer")
    }

    private static var scriptURL: URL {
        sourceDirectory.appendingPathComponent("highlight.min.js")
    }

    private func makeEngine() -> FilePreviewHighlightJavaScriptEngine {
        FilePreviewHighlightJavaScriptEngine(sourceDirectory: Self.sourceDirectory)
    }

    private func fullRange(_ text: String) -> NSRange {
        NSRange(location: 0, length: (text as NSString).length)
    }

    private func role(
        _ runs: [FilePreviewHighlightRun], coveringSubstring needle: String, of text: String
    ) -> FilePreviewTokenRole? {
        let target = (text as NSString).range(of: needle)
        guard target.location != NSNotFound else { return nil }
        return runs.first { NSIntersectionRange($0.range, target).length == target.length }?.role
    }

    @Test("the bundled script exists where the engine expects it")
    func bundledScriptExists() {
        #expect(FileManager.default.fileExists(atPath: Self.scriptURL.path))
    }

    @Test("swift keywords, strings, and comments are classified")
    func swiftBasics() async {
        let text = """
            import Foundation
            // a line comment
            let greeting = "hello"
            let count = 42
            """
        let runs = await makeEngine().runs(for: text, language: "swift", range: fullRange(text))

        #expect(!runs.isEmpty)
        #expect(role(runs, coveringSubstring: "import", of: text) == .keyword)
        #expect(role(runs, coveringSubstring: "// a line comment", of: text) == .comment)
        #expect(role(runs, coveringSubstring: "\"hello\"", of: text) == .string)
        #expect(role(runs, coveringSubstring: "42", of: text) == .number)
    }

    @Test("ranges are absolute document offsets, not relative to the requested window")
    func rangesAreAbsolute() async {
        let prefix = String(repeating: "\n", count: 20)
        let text = prefix + "let x = 1"
        let window = NSRange(location: (prefix as NSString).length, length: 9)
        let runs = await makeEngine().runs(for: text, language: "swift", range: window)

        #expect(!runs.isEmpty)
        for run in runs {
            #expect(
                run.range.location >= window.location,
                "run at \(run.range.location) precedes the window, so offsets are relative"
            )
        }
        #expect(role(runs, coveringSubstring: "let", of: text) == .keyword)
    }

    @Test("a block comment opening before the window is still a comment inside it")
    func blockCommentOpeningBeforeWindow() async {
        // The reason the seam passes the whole document: handed only the window, the
        // engine would read this tail as ordinary code.
        let opening = "/* opening line\n"
        let text = opening + "still inside the comment\n*/\nlet after = 1"
        let tail = NSRange(
            location: (opening as NSString).length,
            length: (text as NSString).length - (opening as NSString).length
        )
        let runs = await makeEngine().runs(for: text, language: "swift", range: tail)

        let insideRange = (text as NSString).range(of: "still inside the comment")
        let covering = runs.first { NSIntersectionRange($0.range, insideRange).length > 0 }
        #expect(covering?.role == .comment)
    }

    @Test("an unknown language yields no runs instead of failing")
    func unknownLanguageIsEmpty() async {
        let text = "let x = 1"
        let runs = await makeEngine().runs(for: text, language: "not-a-language", range: fullRange(text))
        #expect(runs.isEmpty)
    }

    @Test("empty text yields no runs")
    func emptyTextIsEmpty() async {
        let runs = await makeEngine().runs(for: "", language: "swift", range: NSRange(location: 0, length: 0))
        #expect(runs.isEmpty)
    }

    @Test("a missing script degrades to plain text rather than trapping")
    func missingScriptIsEmpty() async {
        let engine = FilePreviewHighlightJavaScriptEngine(
            sourceDirectory: URL(fileURLWithPath: "/nonexistent")
        )
        let text = "let x = 1"
        #expect(await engine.runs(for: text, language: "swift", range: fullRange(text)).isEmpty)
    }

    @Test("runs never escape the document bounds")
    func runsStayInsideDocument() async {
        let text = "let value = \"multi\\nline\"\n// tail"
        let runs = await makeEngine().runs(for: text, language: "swift", range: fullRange(text))
        let length = (text as NSString).length
        for run in runs {
            #expect(run.range.location >= 0)
            #expect(run.range.location + run.range.length <= length)
        }
    }

    @Test("representative languages all produce runs")
    func representativeLanguagesProduceRuns() async {
        let samples: [(language: String, text: String)] = [
            ("typescript", "const x: number = 1; // note"),
            ("javascript", "const x = 'a'; // note"),
            ("python", "def f():\n    return 'a'  # note"),
            ("json", "{\"a\": 1, \"b\": true}"),
            ("yaml", "key: value # note"),
            ("markdown", "# Title\n\nSome `code` here."),
            ("c", "int main(void) { return 0; } // note"),
            ("cpp", "#include <vector>\nint main() { return 0; }"),
            ("rust", "fn main() { let x = 1; } // note"),
            ("go", "package main\nfunc main() { _ = 1 }"),
            ("php", "<?php $x = 'a'; // note"),
        ]
        let engine = makeEngine()
        for sample in samples {
            let runs = await engine.runs(
                for: sample.text, language: sample.language, range: fullRange(sample.text)
            )
            #expect(!runs.isEmpty, "\(sample.language) produced no runs")
        }
    }

    @Test("dart works through the vendored grammar")
    func dartIsSupported() async {
        // The bundled highlight.js is the "common" build and has no dart grammar; the
        // matching 11.10.0 grammar is vendored next to it. This is what proves the extra
        // grammar is actually being loaded, rather than the language silently falling back
        // to plain text the way an unknown extension would.
        let text = """
            // a dart comment
            void main() {
              var greeting = 'hello';
              int count = 42;
            }
            """
        let runs = await makeEngine().runs(for: text, language: "dart", range: fullRange(text))

        #expect(!runs.isEmpty, "dart produced no runs; the vendored grammar is not loading")
        #expect(role(runs, coveringSubstring: "// a dart comment", of: text) == .comment)
        #expect(role(runs, coveringSubstring: "'hello'", of: text) == .string)
        #expect(role(runs, coveringSubstring: "42", of: text) == .number)
    }

    @Test("the vendored grammar file is present")
    func vendoredGrammarExists() {
        for grammar in FilePreviewHighlightJavaScriptEngine.additionalGrammars {
            let url = Self.scriptURL
                .deletingLastPathComponent()
                .appendingPathComponent("\(grammar).min.js")
            #expect(
                FileManager.default.fileExists(atPath: url.path),
                "\(grammar).min.js is listed in additionalGrammars but not vendored"
            )
        }
    }
}
