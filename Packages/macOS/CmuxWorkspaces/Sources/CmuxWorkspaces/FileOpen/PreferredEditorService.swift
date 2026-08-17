public import Foundation
public import CmuxSettings
public import CmuxTestSupport

/// Opens files in the user's preferred editor, falling back to the system
/// default handler — the launch path lifted from the legacy
/// `PreferredEditorSettings.open`.
///
/// Behavior, kept faithful to the legacy namespace:
/// 1. When a UI-test capture file is configured under
///    `CMUX_UI_TEST_CAPTURE_OPEN_PATH`, the open is recorded there and
///    intercepted (no process or system open).
/// 2. With no configured editor command, the file opens with the system
///    default handler.
/// 3. Otherwise `/bin/sh -c "<command> '<path>'"` is spawned with silenced
///    stdio; a launch failure or a nonzero exit (e.g. command-not-found
///    exiting 127) falls back to the system default handler.
///
/// Isolation: `@MainActor`, because every caller is a main-thread UI flow
/// and the legacy code spawned the editor process synchronously on the
/// calling (main) thread; co-locating keeps the spawn timing identical.
/// Exit status is observed via `Process.terminationHandler` (replacing the
/// legacy `DispatchQueue.global` + `waitUntilExit` hop); the handler hops
/// back to the main actor for the fallback open, matching the legacy
/// `DispatchQueue.main.async` fallback.
@MainActor
public struct PreferredEditorService: FileOpening {
    private let editor: any PreferredEditorReading
    private let capture: any TestCaptureWriting
    private let systemOpener: any SystemFileOpening

    /// Creates a service with explicit collaborators (tests pass fakes).
    ///
    /// - Parameters:
    ///   - editor: Source of the configured editor command.
    ///   - capture: UI-test capture seam consulted before any real open.
    ///   - systemOpener: Fallback opener for the no-command and
    ///     failed-command paths.
    public init(
        editor: any PreferredEditorReading,
        capture: any TestCaptureWriting,
        systemOpener: any SystemFileOpening
    ) {
        self.editor = editor
        self.capture = capture
        self.systemOpener = systemOpener
    }

    /// Creates the production service: editor command from `defaults`,
    /// capture from the process environment, fallback through `NSWorkspace`.
    /// Token a preferred-editor command uses to receive the quoted file path.
    public static let filePlaceholder = "{file}"

    /// Token a preferred-editor command uses to receive the line number.
    public static let linePlaceholder = "{line}"

    /// Builds the `/bin/sh -c` script for one open.
    ///
    /// Exposed because the quoting rules are the security-relevant part of this type and
    /// deserve to be asserted directly, without spawning a process.
    ///
    /// Substitution rules:
    /// - ``filePlaceholder`` is replaced with the **already single-quoted** path. Callers
    ///   never build the quoting themselves, so a file name containing `'` cannot end the
    ///   quoted string and inject shell words.
    /// - ``linePlaceholder`` is replaced with a decimal `Int`. Because the parameter is
    ///   typed `Int?`, no caller-supplied text ever reaches the script through it.
    /// - A command carrying only ``linePlaceholder`` still receives the path, appended in
    ///   the historical position, so a half-written command degrades instead of running
    ///   with a stray `{line}` in it.
    /// - `nil` becomes line 1: opening at the top of the file is what "no preference"
    ///   means to every editor that takes a line argument.
    ///
    /// ```swift
    /// PreferredEditorService.shellCommand(command: "code --goto {file}:{line}", path: "/a b.swift", line: 12)
    /// // code --goto '/a b.swift':12
    /// ```
    ///
    /// - Parameters:
    ///   - command: Configured editor command, possibly containing placeholders.
    ///   - path: Filesystem path to open.
    ///   - line: 1-based line, or `nil`.
    /// - Returns: Script to hand to `/bin/sh -c`.
    public static func shellCommand(command: String, path: String, line: Int?) -> String {
        let quotedPath = path.posixShellSingleQuoted
        let hasFile = command.contains(filePlaceholder)
        let hasLine = command.contains(linePlaceholder)

        guard hasFile || hasLine else {
            return "\(command) \(quotedPath)"
        }

        var script = command.replacingOccurrences(of: linePlaceholder, with: String(line ?? 1))
        if hasFile {
            script = script.replacingOccurrences(of: filePlaceholder, with: quotedPath)
        } else {
            script += " \(quotedPath)"
        }
        return script
    }

    public init(defaults: UserDefaults) {
        self.init(
            editor: PreferredEditorSettingsStore(defaults: defaults),
            capture: UITestCaptureSink(),
            systemOpener: NSWorkspaceFileOpener()
        )
    }

    public func open(_ url: URL) {
        open(url, line: nil)
    }

    /// Opens `url`, asking the editor to place the caret on `line` when it can.
    ///
    /// Only the configured-command path can carry a line number; the system-default
    /// fallback has nowhere to put one, so `line` is dropped there and the file still
    /// opens. That is deliberate — a file that opens at the wrong line beats a file that
    /// does not open.
    ///
    /// The command opts in by containing ``filePlaceholder`` or ``linePlaceholder``. A
    /// command without either keeps the historical shape (`<command> '<path>'`), so
    /// existing configurations are unaffected.
    ///
    /// - Parameters:
    ///   - url: File to open.
    ///   - line: 1-based line, or `nil` for no preference.
    public func open(_ url: URL, line: Int?) {
        if capture.appendLineIfConfigured(
            envKey: "CMUX_UI_TEST_CAPTURE_OPEN_PATH",
            line: url.path
        ) {
            return
        }

        guard let command = editor.resolvedCommand else {
            systemOpener.openWithSystemDefault(url)
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", Self.shellCommand(command: command, path: url.path, line: line)]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        let systemOpener = self.systemOpener
        process.terminationHandler = { @Sendable process in
            // Fall back when the command fails (e.g. command not found exits
            // 127 but /bin/sh itself launched fine).
            guard process.terminationStatus != 0 else { return }
            Task { @MainActor in
                systemOpener.openWithSystemDefault(url)
            }
        }

        do {
            try process.run()
        } catch {
            systemOpener.openWithSystemDefault(url)
        }
    }
}
