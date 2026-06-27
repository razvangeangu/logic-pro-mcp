import Testing
@testable import LogicProMCP

/// v3.0.6 — verifies the `library.scan_all` mode dispatch. Ralph round 2
/// requires this test to exist so a future regression that silently flips
/// the default back to the live AX scanner (or drops a mode entirely) is
/// caught by the test suite rather than by end-user reports.
///
/// We exercise `AccessibilityChannel.parseScanMode` directly — a pure,
/// isolated function that is the single source of truth for the
/// `params["mode"] → scanner-branch` decision. The three `runXxxScan`
/// methods (`runLiveScan`, `runDiskScan`, `runBothScan`) are already
/// individually covered by other suites; the only thing we haven't locked
/// down before this test existed was "which one runs for which mode
/// string, and what's the default?".
@Suite("v3.0.6 library.scan_all mode routing")
struct ScanLibraryModeRoutingTests {

    @Test("default (nil) → disk")
    func defaultIsDisk() {
        #expect(AccessibilityChannel.parseScanMode(nil) == .disk)
    }

    @Test("empty string → disk")
    func emptyStringIsDisk() {
        #expect(AccessibilityChannel.parseScanMode("") == .disk)
    }

    @Test("explicit ax → ax")
    func explicitAX() {
        #expect(AccessibilityChannel.parseScanMode("ax") == .ax)
    }

    @Test("explicit disk → disk")
    func explicitDisk() {
        #expect(AccessibilityChannel.parseScanMode("disk") == .disk)
    }

    @Test("explicit both → both")
    func explicitBoth() {
        #expect(AccessibilityChannel.parseScanMode("both") == .both)
    }

    @Test("mixed case (AX, Disk, Both) — normalized to lowercase variant")
    func caseInsensitive() {
        #expect(AccessibilityChannel.parseScanMode("AX") == .ax)
        #expect(AccessibilityChannel.parseScanMode("Disk") == .disk)
        #expect(AccessibilityChannel.parseScanMode("BOTH") == .both)
    }

    @Test("unknown mode falls back to disk")
    func unknownFallsBackToDisk() {
        #expect(AccessibilityChannel.parseScanMode("filesystem") == .disk)
        #expect(AccessibilityChannel.parseScanMode("legacy") == .disk)
        #expect(AccessibilityChannel.parseScanMode("xyz") == .disk)
    }

    @Test("regression: unattended default does not click through live AX panel")
    func regressionNoDefaultToAX() {
        #expect(AccessibilityChannel.parseScanMode(nil) != .ax)
        #expect(AccessibilityChannel.parseScanMode("") != .ax)
    }
}
