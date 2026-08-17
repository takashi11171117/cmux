import Foundation
import Testing

@testable import CmuxSettings

/// Covers socket isolation for forks shipped as their own app.
///
/// A fork's bundle identifier used to fall through to ``SocketPathVariant/stable``, handing it
/// upstream cmux's socket and marker file. Both apps then wrote the same marker and whichever
/// launched last owned the socket, so `cmux send` reached an app the caller never chose. The
/// failure is invisible from either side — the command succeeds, just in the wrong place — so
/// it is pinned here rather than left to be noticed in use.
@Suite("SocketPathVariant fork isolation")
struct SocketPathForkVariantTests {
    private func variant(_ bundleId: String) -> SocketPathVariant {
        SocketPathMarkerFiles.variant(bundleIdentifier: bundleId, environment: [:])
    }

    @Test("a fork identifier resolves to fork, not stable")
    func forkIdentifierIsNotStable() {
        let resolved = variant("com.cmuxterm.app.afide")
        guard case .fork = resolved else {
            Issue.record("expected .fork, got \(resolved)")
            return
        }
    }

    @Test("a fork does not share the marker file with upstream")
    func forkMarkerDiffersFromStable() {
        let fork = variant("com.cmuxterm.app.afide").markerFileName
        let stable = variant(SocketPathMarkerFiles.stableBundleIdentifier).markerFileName
        #expect(fork != stable)
    }

    @Test("a fork does not share the /tmp marker with upstream")
    func forkTmpMarkerDiffersFromStable() {
        let fork = variant("com.cmuxterm.app.afide").tmpPath
        let stable = variant(SocketPathMarkerFiles.stableBundleIdentifier).tmpPath
        #expect(fork != stable)
    }

    @Test("a fork does not share the socket itself with upstream")
    func forkSocketDiffersFromStable() {
        let stablePath = "/Users/test-user/.local/state/cmux/cmux.sock"
        let fork = SocketPathMarkerFiles.defaultSocketPath(
            bundleIdentifier: "com.cmuxterm.app.afide",
            environment: [:],
            isDebugBuild: false,
            stableSocketPath: stablePath
        )
        let stable = SocketPathMarkerFiles.defaultSocketPath(
            bundleIdentifier: SocketPathMarkerFiles.stableBundleIdentifier,
            environment: [:],
            isDebugBuild: false,
            stableSocketPath: stablePath
        )
        #expect(stable == stablePath)
        #expect(fork != stable)
    }

    @Test("a tagged fork build is separate from the untagged fork")
    func taggedForkIsSeparate() {
        let plain = variant("com.cmuxterm.app.afide")
        let tagged = variant("com.cmuxterm.app.afide.mytag")
        #expect(plain.markerFileName != tagged.markerFileName)
        #expect(plain.tmpPath != tagged.tmpPath)
    }

    @Test("every declared fork prefix resolves to fork")
    func allDeclaredPrefixesResolve() {
        for prefix in SocketPathMarkerFiles.forkBundleIdentifierPrefixes {
            guard case .fork = variant(prefix) else {
                Issue.record("\(prefix) did not resolve to .fork")
                continue
            }
        }
    }

    @Test("upstream identifiers keep their existing variants")
    func upstreamVariantsUnchanged() {
        // The fork check runs last, so adding it must not capture anything that already had a
        // home. A fork prefix that accidentally shadowed the debug stem would silently move
        // every tagged dev build onto a different socket.
        guard case .stable = variant(SocketPathMarkerFiles.stableBundleIdentifier) else {
            Issue.record("stable identifier changed variant")
            return
        }
        guard case .nightly = variant(SocketPathMarkerFiles.nightlyBundleIdentifier) else {
            Issue.record("nightly identifier changed variant")
            return
        }
        guard case .staging = variant(SocketPathMarkerFiles.stagingBundleIdentifier) else {
            Issue.record("staging identifier changed variant")
            return
        }
        guard case .dev = variant(SocketPathMarkerFiles.defaultBaseDebugBundleIdentifier) else {
            Issue.record("debug identifier changed variant")
            return
        }
        guard case .dev = variant("\(SocketPathMarkerFiles.defaultBaseDebugBundleIdentifier).sometag") else {
            Issue.record("tagged debug identifier changed variant")
            return
        }
    }

    @Test("an unrelated identifier still falls back to stable")
    func unrelatedIdentifierStaysStable() {
        guard case .stable = variant("com.example.somethingelse") else {
            Issue.record("fallback changed")
            return
        }
    }
}
