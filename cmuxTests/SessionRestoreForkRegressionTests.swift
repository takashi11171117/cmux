import Foundation
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

/// Guards the one thing the fork's editor work must never do: change how sessions decode.
///
/// The fork adds syntax highlighting, line numbers, and a save-conflict banner. None of it
/// touches `SessionPanelSnapshot`, `PanelType`, or any other persisted shape — the toggles
/// live in `UserDefaults` and the highlight runs are derived data. This suite exists to make
/// that claim checkable rather than asserted.
///
/// Why it matters more here than in most features: `PanelType.init(from:)` throws on an
/// unrecognized raw value, and `SessionWorkspaceSnapshot.panels` is a non-optional array
/// with synthesized `Codable`. One unreadable panel type therefore fails the decode of the
/// **entire window snapshot**, not just that pane. A fork that invented its own case would
/// hand users an unrestorable session the moment they ran an upstream build again.
@Suite("Session restore fork regression")
struct SessionRestoreForkRegressionTests {
    /// A snapshot in the on-disk shape that predates the fork's editor work.
    ///
    /// Hand-authored from the key structure of a real pre-implementation session file rather
    /// than copied from one: a live snapshot carries working directories, window titles, and
    /// terminal scrollback. Only the shape is reproduced; every value here is synthetic.
    private static var fixtureURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/session-preimplementation-v1.json")
    }

    private func decodeFixture() throws -> AppSessionSnapshot {
        let data = try Data(contentsOf: Self.fixtureURL)
        return try JSONDecoder().decode(AppSessionSnapshot.self, from: data)
    }

    @Test("the fixture exists where the test expects it")
    func fixtureExists() {
        #expect(FileManager.default.fileExists(atPath: Self.fixtureURL.path))
    }

    @Test("a pre-implementation snapshot still decodes")
    func preImplementationSnapshotDecodes() throws {
        let snapshot = try decodeFixture()
        #expect(snapshot.version == 1)
        #expect(snapshot.windows.count == 1)
    }

    @Test("all five panel kinds survive the decode")
    func allPanelKindsDecode() throws {
        let snapshot = try decodeFixture()
        let window = try #require(snapshot.windows.first)
        let workspace = try #require(window.tabManager.workspaces.first)

        let types = workspace.panels.map(\.type)
        #expect(types.contains(.terminal))
        #expect(types.contains(.browser))
        #expect(types.contains(.markdown))
        #expect(types.contains(.filePreview))
        #expect(types.contains(.project))
        #expect(workspace.panels.count == 5)
    }

    @Test("panel payloads keep their contents")
    func panelPayloadsDecode() throws {
        let snapshot = try decodeFixture()
        let workspace = try #require(snapshot.windows.first?.tabManager.workspaces.first)
        let byType = Dictionary(uniqueKeysWithValues: workspace.panels.map { ($0.type, $0) })

        #expect(byType[.markdown]?.markdown?.filePath.hasSuffix("README.md") == true)
        #expect(byType[.filePreview]?.filePreview?.filePath.hasSuffix("main.swift") == true)
        #expect(byType[.project]?.project?.projectPath.hasSuffix(".xcodeproj") == true)
        #expect(byType[.browser]?.browser?.urlString == "https://example.com/")
        #expect(byType[.terminal]?.terminal != nil)
    }

    @Test("layout and selection survive the decode")
    func layoutDecodes() throws {
        let snapshot = try decodeFixture()
        let workspace = try #require(snapshot.windows.first?.tabManager.workspaces.first)
        #expect(workspace.focusedPanelId != nil)
        #expect(workspace.currentDirectory.isEmpty == false)
    }

    @Test("the fixture round-trips through encode and decode unchanged")
    func fixtureRoundTrips() throws {
        let original = try decodeFixture()
        let encoded = try JSONEncoder().encode(original)
        let reencoded = try JSONDecoder().decode(AppSessionSnapshot.self, from: encoded)

        let originalTypes = original.windows.first?.tabManager.workspaces.first?.panels.map(\.type)
        let reencodedTypes = reencoded.windows.first?.tabManager.workspaces.first?.panels.map(\.type)
        #expect(originalTypes == reencodedTypes)
        #expect(reencoded.version == original.version)
    }

    @Test("an unknown panel type fails the whole snapshot, not just that panel")
    func unknownPanelTypeFailsEntireSnapshot() throws {
        // This is the reason the fork does not add a PanelType case. Documenting the blast
        // radius here means a future change that adds one has to confront it.
        let data = try Data(contentsOf: Self.fixtureURL)
        let text = try #require(String(data: data, encoding: .utf8))
        let mutated = text.replacingOccurrences(of: "\"type\": \"markdown\"", with: "\"type\": \"forkOnlyCase\"")
        #expect(mutated != text, "the fixture should contain a markdown panel to mutate")

        let mutatedData = try #require(mutated.data(using: .utf8))
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(AppSessionSnapshot.self, from: mutatedData)
        }
    }
}
