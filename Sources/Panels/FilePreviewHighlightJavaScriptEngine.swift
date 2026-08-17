import Foundation
import JavaScriptCore

/// Highlights source text with the highlight.js build already bundled for Markdown preview.
///
/// The app ships `Resources/markdown-viewer/highlight.min.js` (11.10.0) to render fenced
/// code blocks in the Markdown web view. Evaluating that same file in a `JSContext`
/// reuses it for the plain-text editor with no SwiftPM dependency, no bundle growth, and
/// no pbxproj change — `JavaScriptCore` is a system framework that Swift auto-links.
///
/// ## Why not the HTML output
///
/// `hljs.highlight()` normally returns an HTML string that would have to be re-parsed to
/// recover offsets. Instead this installs a custom `__emitter`, which highlight.js calls
/// with `startScope` / `endScope` / `addText` as it walks the token tree. Accumulating the
/// text length across those calls yields ranges directly. JavaScript string lengths are in
/// UTF-16 code units, which is exactly what `NSRange` wants, so no transcoding is needed.
///
/// `__emitter` is not public API (hence the underscores). AFIDE-01 verified byte-identical
/// output across 11.10.0, 11.11.1, and 11.12.0, and found no emitter-related breaking
/// change in the changelog from 11.3.1 onward — but an upstream bundle refresh could still
/// break it, which is what ``FilePreviewHighlightJavaScriptEngineTests`` is there to catch.
///
/// ## Cost
///
/// highlight.js scans the whole document regardless of `range`; AFIDE-01 measured
/// 233.9 ms for a 4,475-line file and 231.2 ms for the same file clipped to 3,000
/// characters. Narrowing `range` therefore reduces how much crosses back into Swift, not
/// how long the engine runs. Callers must debounce and respect the size budget rather than
/// relying on a small `range` to stay cheap.
actor FilePreviewHighlightJavaScriptEngine: FilePreviewSyntaxHighlighting {
    private var context: JSContext?
    private var preparationFailed = false
    private let sourceDirectory: URL?

    /// Creates an engine. No JavaScript runs until the first ``runs(for:language:range:)``.
    ///
    /// - Parameter sourceDirectory: Directory holding plain `.js` files. Production passes
    ///   `nil` and reads through ``MarkdownViewerAssets``: the build compresses every
    ///   bundled script to `<name>.js.deflate` and **deletes the original**, so looking for
    ///   `highlight.min.js` inside the app bundle finds nothing. Tests pass the checked-in
    ///   `Resources/markdown-viewer` directory, where the files are still plain.
    init(sourceDirectory: URL? = nil) {
        self.sourceDirectory = sourceDirectory
    }

    /// Language grammars vendored next to the core script.
    ///
    /// The bundled highlight.js is the "common" build (36 languages) and has no Dart, so
    /// `dart.min.js` from the same 11.10.0 release sits beside it. Adding a row here means
    /// dropping the matching `<name>.min.js` into `Resources/markdown-viewer/`; that folder
    /// is a pbxproj *folder reference*, so new files need no project-file change.
    static let additionalGrammars = ["dart"]

    /// Reads one script, from the injected directory in tests or the app bundle otherwise.
    ///
    /// The bundle path goes through ``MarkdownViewerAssets`` rather than `Bundle.main.url`
    /// because that type already inflates the build-time `.deflate` form and caches it, so
    /// the Markdown viewer and the editor share one copy of the 125 KB script.
    private func loadSource(name: String) async -> String? {
        if let sourceDirectory {
            return try? String(
                contentsOf: sourceDirectory.appendingPathComponent("\(name).js"), encoding: .utf8
            )
        }
        // `await`, not `MainActor.assumeIsolated`. This type is an actor with its own
        // executor, so it does not run on the main thread and asserting that it does traps
        // at runtime (SIGTRAP). The hop happens once per engine, during lazy preparation.
        return await MainActor.run {
            MarkdownViewerAssets.shared.optionalAsset(name: name, ext: "js")
        }
    }

    func runs(for text: String, language: String, range: NSRange) async -> [FilePreviewHighlightRun] {
        guard !text.isEmpty, let context = await preparedContext() else { return [] }

        let highlight = context.objectForKeyedSubscript("cmuxHighlight")
        guard let highlight, !highlight.isUndefined, !highlight.isNull else { return [] }

        guard let result = highlight.call(withArguments: [text, language]) else { return [] }
        guard !result.isUndefined, !result.isNull else { return [] }

        return decode(result, clippingTo: range, documentLength: (text as NSString).length)
    }

    /// Returns the prepared context, building it on first use.
    ///
    /// A failed preparation is remembered so a broken or missing bundle costs one attempt
    /// rather than one attempt per keystroke.
    private func preparedContext() async -> JSContext? {
        if let context { return context }
        guard !preparationFailed else { return nil }

        guard
            let script = await loadSource(name: "highlight.min"),
            let created = JSContext()
        else {
            preparationFailed = true
            return nil
        }

        created.exceptionHandler = { _, _ in }
        created.evaluateScript(script)

        guard let hljs = created.objectForKeyedSubscript("hljs"), !hljs.isUndefined else {
            preparationFailed = true
            return nil
        }

        // Grammars the bundled "common" build leaves out, vendored alongside it. Loaded
        // after the core script because each one calls `hljs.registerLanguage` on the
        // global the core defines. A missing file is skipped rather than fatal: the
        // language then behaves like any other unknown extension and renders plain.
        for grammar in Self.additionalGrammars {
            guard let source = await loadSource(name: "\(grammar).min") else { continue }
            created.evaluateScript(source)
        }

        created.setObject(Self.scopeRoleIdentifiers, forKeyedSubscript: "cmuxScopeRoles" as NSString)
        created.evaluateScript(Self.emitterScript)

        guard
            let entry = created.objectForKeyedSubscript("cmuxHighlight"),
            !entry.isUndefined
        else {
            preparationFailed = true
            return nil
        }

        context = created
        return created
    }

    /// Converts the flat `[location, length, roleID, ...]` array into runs.
    ///
    /// Clips to `range` and to the document so a malformed engine reply cannot produce an
    /// out-of-bounds `NSRange`; the controller clamps again at apply time, because a single
    /// unclamped path is enough to raise `NSRangeException`.
    private func decode(
        _ value: JSValue, clippingTo range: NSRange, documentLength: Int
    ) -> [FilePreviewHighlightRun] {
        guard let flat = value.toArray() as? [NSNumber], flat.count % 3 == 0 else { return [] }

        let document = NSRange(location: 0, length: documentLength)
        let window = NSIntersectionRange(range, document)
        var runs: [FilePreviewHighlightRun] = []
        runs.reserveCapacity(flat.count / 3)

        for start in stride(from: 0, to: flat.count, by: 3) {
            let location = flat[start].intValue
            let length = flat[start + 1].intValue
            guard length > 0, location >= 0 else { continue }

            let candidate = NSIntersectionRange(
                NSRange(location: location, length: length), document
            )
            guard candidate.length > 0 else { continue }
            guard window.length == 0 || NSIntersectionRange(candidate, window).length > 0 else { continue }

            let role = Self.role(forIdentifier: flat[start + 2].intValue)
            guard role != .plain else { continue }
            runs.append(FilePreviewHighlightRun(range: candidate, role: role))
        }
        return runs
    }

    /// Maps the numeric id used on the JavaScript side back to a role.
    private static func role(forIdentifier identifier: Int) -> FilePreviewTokenRole {
        switch identifier {
        case 1: .keyword
        case 2: .string
        case 3: .comment
        case 4: .number
        case 5: .type
        case 6: .attribute
        default: .plain
        }
    }

    /// highlight.js scope name to role id, injected into the context as `cmuxScopeRoles`.
    ///
    /// Declared once here rather than duplicated in the JavaScript source, so adding a
    /// scope is a one-line Swift change. Scopes absent from this table fall through to
    /// `plain` and are dropped, which is why `operator`, `punctuation`, `params`, and
    /// `variable` are deliberately missing: coloring them makes ordinary code look
    /// confetti-like without helping anyone read it.
    private static let scopeRoleIdentifiers: [String: Int] = [
        "keyword": 1,
        "variable.language": 1,
        "string": 2,
        "subst": 2,
        "regexp": 2,
        "char": 2,
        "template-variable": 2,
        "code": 2,
        "formula": 2,
        "comment": 3,
        "doctag": 3,
        "quote": 3,
        "number": 4,
        "literal": 4,
        "symbol": 4,
        "type": 5,
        "title": 5,
        "title.class": 5,
        "title.class.inherited": 5,
        "title.function": 5,
        "title.function.invoke": 5,
        "built_in": 5,
        "class": 5,
        "name": 5,
        "tag": 5,
        "section": 5,
        "selector-tag": 5,
        "attr": 6,
        "attribute": 6,
        "meta": 6,
        "meta.prompt": 6,
        "property": 6,
        "selector-attr": 6,
        "selector-class": 6,
        "selector-id": 6,
        "selector-pseudo": 6,
    ]

    /// Emitter that records ranges instead of building HTML, plus the `cmuxHighlight` entry point.
    ///
    /// Implements every method highlight.js 11 may call on an emitter. `toHTML` returns an
    /// empty string because the HTML is exactly the work being avoided; `__addSublanguage`
    /// folds a nested language's runs in at the right offset so a `<script>` block inside
    /// HTML still colors.
    private static let emitterScript = """
        (function () {
          function CmuxRangeEmitter(options) {
            this.options = options;
            this.stack = [];
            this.offset = 0;
            this.runs = [];
          }
          CmuxRangeEmitter.prototype.addText = function (text) {
            if (text) { this.offset += text.length; }
          };
          CmuxRangeEmitter.prototype.startScope = function (scope) {
            this.stack.push({ scope: scope, start: this.offset });
          };
          CmuxRangeEmitter.prototype.endScope = function () {
            var open = this.stack.pop();
            if (!open) { return; }
            var role = cmuxScopeRoles[open.scope];
            if (role === undefined && typeof open.scope === "string") {
              var dot = open.scope.indexOf(".");
              if (dot > 0) { role = cmuxScopeRoles[open.scope.substring(0, dot)]; }
            }
            if (role === undefined) { return; }
            var length = this.offset - open.start;
            if (length > 0) { this.runs.push(open.start, length, role); }
          };
          CmuxRangeEmitter.prototype.__addSublanguage = function (emitter, name) {
            var base = this.offset;
            if (emitter && emitter.runs) {
              for (var i = 0; i < emitter.runs.length; i += 3) {
                this.runs.push(emitter.runs[i] + base, emitter.runs[i + 1], emitter.runs[i + 2]);
              }
              this.offset = base + emitter.offset;
            }
          };
          CmuxRangeEmitter.prototype.openNode = function (scope) { this.startScope(scope); };
          CmuxRangeEmitter.prototype.closeNode = function () { this.endScope(); };
          CmuxRangeEmitter.prototype.finalize = function () {};
          CmuxRangeEmitter.prototype.toHTML = function () { return ""; };

          hljs.configure({ __emitter: CmuxRangeEmitter });

          cmuxHighlight = function (text, language) {
            try {
              if (!hljs.getLanguage(language)) { return []; }
              var result = hljs.highlight(text, { language: language, ignoreIllegals: true });
              var emitter = result && result._emitter;
              return emitter && emitter.runs ? emitter.runs : [];
            } catch (error) {
              return [];
            }
          };
        })();
        """
}
