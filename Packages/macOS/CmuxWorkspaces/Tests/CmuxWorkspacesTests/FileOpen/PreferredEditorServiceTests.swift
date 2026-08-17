import Foundation
import Testing
@testable import CmuxWorkspaces
import CmuxSettings
import CmuxTestSupport

@MainActor
private final class RecordingSystemOpener: SystemFileOpening {
    private(set) var openedURLs: [URL] = []
    var onOpen: (@MainActor () -> Void)?

    func openWithSystemDefault(_ url: URL) {
        openedURLs.append(url)
        onOpen?()
    }
}

private struct FixedEditor: PreferredEditorReading {
    var resolvedCommand: String?
}

@Suite("PreferredEditorService")
@MainActor
struct PreferredEditorServiceTests {
    private func makeScratchDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cmux-file-open-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func commandWithoutPlaceholdersKeepsHistoricalShape() {
        // Existing configurations must be untouched by the line-number feature.
        let script = PreferredEditorService.shellCommand(
            command: "code", path: "/tmp/a.swift", line: 12
        )
        #expect(script == "code '/tmp/a.swift'")
    }

    @Test func filePlaceholderReceivesTheQuotedPath() {
        let script = PreferredEditorService.shellCommand(
            command: "code --goto {file}:{line}", path: "/tmp/a b.swift", line: 12
        )
        #expect(script == "code --goto '/tmp/a b.swift':12")
    }

    @Test func nilLineOpensAtTheTop() {
        let script = PreferredEditorService.shellCommand(
            command: "code --goto {file}:{line}", path: "/tmp/a.swift", line: nil
        )
        #expect(script == "code --goto '/tmp/a.swift':1")
    }

    @Test func lineOnlyCommandStillReceivesThePath() {
        // A half-written command degrades to opening the file rather than running with a
        // literal {line} in it.
        let script = PreferredEditorService.shellCommand(
            command: "myeditor --line {line}", path: "/tmp/a.swift", line: 7
        )
        #expect(script == "myeditor --line 7 '/tmp/a.swift'")
    }

    @Test func apostropheInPathCannotEscapeTheQuotes() {
        // The whole point of routing the path through posixShellSingleQuoted: a file named
        // with a quote must not be able to terminate the quoted word and append commands.
        let script = PreferredEditorService.shellCommand(
            command: "code --goto {file}:{line}", path: "/tmp/it's; rm -rf ~.swift", line: 3
        )
        #expect(script == #"code --goto '/tmp/it'\''s; rm -rf ~.swift':3"#)
        #expect(!script.contains("; rm -rf ~.swift';"), "the injection payload must stay inside quotes")
    }

    @Test func xedStyleCommandIsSupported() {
        let script = PreferredEditorService.shellCommand(
            command: "xed --line {line} {file}", path: "/tmp/a.swift", line: 42
        )
        #expect(script == "xed --line 42 '/tmp/a.swift'")
    }

    @Test func placeholdersAppearingTwiceAreAllSubstituted() {
        let script = PreferredEditorService.shellCommand(
            command: "e {file} --also {file} --line {line}", path: "/tmp/a.swift", line: 5
        )
        #expect(script == "e '/tmp/a.swift' --also '/tmp/a.swift' --line 5")
    }

    @Test func configuredCaptureInterceptsTheOpen() throws {
        let scratch = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: scratch) }
        let captureFile = scratch.appendingPathComponent("opens.txt")
        let opener = RecordingSystemOpener()
        let service = PreferredEditorService(
            editor: FixedEditor(resolvedCommand: "/usr/bin/false"),
            capture: UITestCaptureSink(
                environment: ["CMUX_UI_TEST_CAPTURE_OPEN_PATH": captureFile.path]
            ),
            systemOpener: opener
        )

        service.open(URL(fileURLWithPath: "/tmp/captured file.md"))

        let contents = try String(contentsOf: captureFile, encoding: .utf8)
        #expect(contents == "/tmp/captured file.md\n")
        #expect(opener.openedURLs.isEmpty)
    }

    @Test func noConfiguredCommandFallsBackToSystemOpen() {
        let opener = RecordingSystemOpener()
        let service = PreferredEditorService(
            editor: FixedEditor(resolvedCommand: nil),
            capture: UITestCaptureSink(environment: [:]),
            systemOpener: opener
        )
        let url = URL(fileURLWithPath: "/tmp/plain.txt")

        service.open(url)

        #expect(opener.openedURLs == [url])
    }

    @Test func configuredCommandReceivesTheQuotedPathAsItsArgument() async throws {
        let scratch = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: scratch) }
        let marker = scratch.appendingPathComponent("received.txt")
        let script = scratch.appendingPathComponent("editor.sh")
        try #"""
        #!/bin/sh
        printf %s "$1" > '\#(marker.path)'
        """#.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: script.path
        )

        let opener = RecordingSystemOpener()
        let service = PreferredEditorService(
            editor: FixedEditor(resolvedCommand: script.path),
            capture: UITestCaptureSink(environment: [:]),
            systemOpener: opener
        )
        // A path needing quoting: spaces and an embedded single quote.
        let awkwardPath = "/tmp/it's a file.md"

        service.open(URL(fileURLWithPath: awkwardPath))

        // Bounded wait for the spawned editor script to write the marker;
        // the script signals completion by creating the file.
        for _ in 0..<200 where !FileManager.default.fileExists(atPath: marker.path) {
            try await Task.sleep(for: .milliseconds(25))
        }
        let received = try String(contentsOf: marker, encoding: .utf8)
        #expect(received == awkwardPath)
        #expect(opener.openedURLs.isEmpty)
    }

    @Test func failingCommandFallsBackToSystemOpen() async {
        let opener = RecordingSystemOpener()
        let service = PreferredEditorService(
            editor: FixedEditor(resolvedCommand: "/usr/bin/false"),
            capture: UITestCaptureSink(environment: [:]),
            systemOpener: opener
        )
        let url = URL(fileURLWithPath: "/tmp/should-fall-back.txt")

        await withCheckedContinuation { continuation in
            opener.onOpen = { continuation.resume() }
            service.open(url)
        }

        #expect(opener.openedURLs == [url])
    }
}
