import Foundation
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

/// The power actions behind Sleepy Mode's buttons and the menu bar's
/// "Sleep Display Now".
///
/// Everything here runs against an injected fake runner: the real implementation shells
/// out to `pmset`, and a test that actually ran it would blank the machine running the
/// suite. What is worth pinning is the exact command, since a typo in the subcommand
/// fails silently — `pmset` exits non-zero, nothing happens, and the menu item just
/// looks broken.
@MainActor
@Suite("Sleepy power controls")
struct SleepyPowerControlsTests {
    @Test("Sleep Display runs `pmset displaysleepnow` and nothing privileged")
    func sleepDisplayRunsDisplaySleepNow() async {
        let runner = RecordingRunner()
        let controls = SleepyPowerControls(runner: runner, defaults: Self.isolatedDefaults())

        await controls.sleepDisplayNow()

        #expect(await runner.commands == [Command(tool: "/usr/bin/pmset", args: ["displaysleepnow"])])
        // Turning the display off must never prompt for admin rights.
        #expect(await runner.privilegedCommands.isEmpty)
    }

    @Test("Lock Mac uses the supported CGSession suspend, not a private symbol")
    func lockMacUsesCGSessionSuspend() async {
        let runner = RecordingRunner()
        let controls = SleepyPowerControls(runner: runner, defaults: Self.isolatedDefaults())

        await controls.lockMacNow()

        #expect(await runner.commands == [Command(
            tool: "/System/Library/CoreServices/Menu Extras/User.menu/Contents/Resources/CGSession",
            args: ["-suspend"]
        )])
    }

    // MARK: - Helpers

    private static func isolatedDefaults() -> UserDefaults {
        let suite = "SleepyPowerControlsTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private struct Command: Equatable, Sendable {
        let tool: String
        let args: [String]
    }

    private actor RecordingRunner: SleepyCommandRunning {
        var commands: [Command] = []
        var privilegedCommands: [Command] = []
        /// What `capture` returns; the display-sleep path never reads it.
        var captureOutput: String?

        func run(_ tool: String, _ args: [String]) async {
            commands.append(Command(tool: tool, args: args))
        }

        func capture(_ tool: String, _ args: [String]) async -> String? {
            captureOutput
        }

        @discardableResult
        func runPrivileged(_ tool: String, _ args: [String]) async -> Bool {
            privilegedCommands.append(Command(tool: tool, args: args))
            return true
        }
    }
}
