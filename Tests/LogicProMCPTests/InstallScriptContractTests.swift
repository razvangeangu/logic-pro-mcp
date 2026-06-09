import Foundation
import Testing

private func repositoryRootURL() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}

private func scriptContents(_ relativePath: String) throws -> String {
    try String(contentsOf: repositoryRootURL().appendingPathComponent(relativePath), encoding: .utf8)
}

@Test func testInstallScriptRequiresPinnedReleaseVerificationByDefault() throws {
    let script = try scriptContents("Scripts/install.sh")

    #expect(script.contains("LOGIC_PRO_MCP_VERSION"))
    #expect(script.contains("LOGIC_PRO_MCP_SHA256"))
    #expect(script.contains("mutable 'latest' installs are not allowed in enterprise mode"))
    #expect(script.contains("Fetching release SHA256 manifest"))
}

@Test func testInstallScriptIncludesSignatureAndGatekeeperVerification() throws {
    let script = try scriptContents("Scripts/install.sh")

    #expect(script.contains("verify_signature()"))
    #expect(script.contains("verify_gatekeeper()"))
    #expect(script.contains("codesign --verify --strict --verbose=2"))
    #expect(script.contains("spctl --assess --type execute"))
    #expect(script.contains("RELEASE-METADATA.json"))
    #expect(script.contains("could not resolve TeamIdentifier from release metadata"))
}

@Test func testInstallScriptExtractsTeamIDFromSingleLineReleaseMetadata() throws {
    let script = try scriptContents("Scripts/install.sh")

    #expect(script.contains("METADATA_JSON=$(curl -fsSL \"$METADATA_URL\")"))
    #expect(script.contains("\"team_id\"[[:space:]]*:[[:space:]]*\""))
    #expect(!script.contains("awk -F'\"' '/\"team_id\"[[:space:]]*:/ {print $4; exit}'"))
}

@Test func testInstallScriptRegistersClaudeAndKeyCommandsByDefault() throws {
    let script = try scriptContents("Scripts/install.sh")

    #expect(script.contains("LOGIC_PRO_MCP_REGISTER_CLAUDE"))
    #expect(script.contains("Registering with Claude Code"))
    #expect(script.contains("LOGIC_PRO_MCP_INSTALL_KEYCMDS"))
    // RB-6 (v3.4.0): wording was "Installing Key Commands preset" — corrected to
    // "Staging Key Commands mapping reference" since Logic 12.2 doesn't actually
    // import the .plist; the script only stages a CC→Command mapping reference
    // for Manual MIDI Learn.
    #expect(script.contains("Staging Key Commands mapping reference"))
    #expect(script.contains("LOGIC_PRO_MCP_INSTALL_DIR"))
    #expect(script.contains("LOGIC_PRO_MCP_SKIP_SUDO"))
    #expect(script.contains("--approve-channel MIDIKeyCommands"))
    #expect(script.contains("--approve-channel Scripter"))
}

@Test func testReleaseWorkflowDualModesAndPublishesMetadata() throws {
    let workflow = try scriptContents(".github/workflows/release.yml")

    // Dual-mode release: Developer ID credentials produce notarized artifacts;
    // otherwise stable and prerelease tags use the historical ADHOC path.
    #expect(workflow.contains("Detect release mode"))
    #expect(workflow.contains("mode=notarized"))
    #expect(workflow.contains("mode=adhoc"))
    #expect(workflow.contains("Publishing ADHOC stable release"))
    #expect(!workflow.contains("Stable ADHOC releases are not permitted"))
    #expect(!workflow.contains("Do not push stable tags manually"))
    #expect(!workflow.contains("ALLOW_ADHOC_STABLE"))
    #expect(workflow.contains("Validate notarization secrets"))
    #expect(workflow.contains("is required for a notarized release build"))
    #expect(workflow.contains("Codesign binary (Developer ID)"))
    #expect(workflow.contains("Codesign binary (ADHOC)"))
    #expect(workflow.contains("codesign --force --sign - LogicProMCP"))
    #expect(workflow.contains("RELEASE-METADATA.json"))
    #expect(workflow.contains("validate-install"))
    #expect(workflow.contains("macos-15"))
    #expect(workflow.contains("macos-14"))
    #expect(workflow.contains("LOGIC_PRO_MCP_INSTALL_DIR"))
}

@Test func testReleaseWorkflowMarksHyphenTagsAsPrereleases() throws {
    let workflow = try scriptContents(".github/workflows/release.yml")

    #expect(workflow.contains("prerelease: ${{ contains(github.ref_name, '-') }}"))
}

@Test func testCoverageWorkflowFailsClosedAndUsesWritableProfilePath() throws {
    let workflow = try scriptContents(".github/workflows/ci.yml")

    #expect(workflow.contains("set -euo pipefail"))
    #expect(workflow.contains("PROFRAW_DIR=\"$RUNNER_TEMP/logicpromcp-profraw\""))
    #expect(workflow.contains("export LLVM_PROFILE_FILE=\"$PROFRAW_DIR/%m-%p.profraw\""))
    #expect(workflow.contains("COVERAGE_LOG=\"$RUNNER_TEMP/logicpromcp-coverage.log\""))
    #expect(workflow.contains("PROFILE_WARNING_COUNT=$(grep -c \"LLVM Profile Error\" \"$COVERAGE_LOG\" || true)"))
    #expect(workflow.contains("continuing to profdata/report validation"))
    #expect(workflow.contains("LLVM profile warnings: ${PROFILE_WARNING_COUNT:-0}."))
    #expect(workflow.contains("MIN_REGION=70"))
    #expect(workflow.contains("MIN_LINE=78"))
    #expect(workflow.contains("COVERAGE_TARGET=90"))
    #expect(!workflow.contains("set +e"))
    #expect(!workflow.contains("lets transient instrumentation flakes"))
}

@Test func testLiveE2EHarnessRoutesCoverageProfilesToWritableTempDir() throws {
    let python = try scriptContents("Scripts/live-e2e-test.py")
    let shell = try scriptContents("Scripts/live-e2e-test.sh")

    #expect(python.contains("def coverage_environment():"))
    #expect(python.contains("LOGIC_PRO_MCP_PROFILE_DIR"))
    #expect(python.contains("LLVM_PROFILE_FILE"))
    #expect(python.contains("%m-%p.profraw"))
    #expect(python.contains("env=coverage_environment()"))
    #expect(python.contains("export LLVM_PROFILE_FILE="))

    #expect(shell.contains("LOGIC_PRO_MCP_PROFILE_DIR"))
    #expect(shell.contains("LLVM_PROFILE_FILE"))
    #expect(shell.contains("%m-%p.profraw"))
    #expect(shell.contains("export LLVM_PROFILE_FILE"))
}

@Test func testScriptsFolderNoLongerShipsOneOffSpikeHarnesses() {
    let root = repositoryRootURL()
    let legacyPaths = [
        "Scripts/analysis-to-logic.py",
        "Scripts/issue7_live_verify.sh",
        "Scripts/probes/library-ax-probe.swift",
        "Scripts/probes/plugin-detective.swift",
        "Scripts/probes/plugin-menu-ax-probe.swift",
        "Scripts/probes/setting-popup-probe.swift",
    ]

    for relativePath in legacyPaths {
        #expect(
            !FileManager.default.fileExists(atPath: root.appendingPathComponent(relativePath).path),
            "\(relativePath) was a one-off local/spike harness and must not ship in Scripts/"
        )
    }
}

@Test func testLocalReleaseScriptSupportsStableAdhocAndFailsClosedOnRemoteCheck() throws {
    let script = try scriptContents("Scripts/release.sh")

    #expect(script.contains("local one-command ADHOC release"))
    #expect(script.contains("Scripts/release.sh v3.0.1"))
    #expect(!script.contains("refuses stable tags"))
    #expect(!script.contains("There is intentionally no override"))
    #expect(!script.contains("LOGIC_PRO_MCP_ALLOW_ADHOC_STABLE"))
    #expect(script.contains("RELEASE_FLAGS=\"--prerelease\""))
    #expect(script.contains("could not verify remote tag availability"))
    #expect(script.contains("Refusing to continue because publishing could race"))
}

@Test func testStableReleaseScriptPreflightsAdhocTagBeforePush() throws {
    let script = try scriptContents("Scripts/release-stable.sh")

    #expect(script.contains("stable ADHOC release preflight"))
    #expect(!script.contains("gh secret list --repo \"$REPO\" --app actions"))
    #expect(!script.contains("Stable tag '$VERSION' was NOT created."))
    #expect(!script.contains("MACOS_CERT_BASE64"))
    #expect(!script.contains("APPLE_NOTARY_APPLE_ID"))
    #expect(script.contains("refs/tags/$VERSION"))
    #expect(script.contains("gh release view \"$VERSION\""))
    #expect(script.contains("python3 -m py_compile Scripts/live-e2e-test.py"))
    #expect(script.contains("swift test --no-parallel"))
    #expect(script.contains("swift build -c release"))
    #expect(script.contains("git push origin \"$VERSION\""))
}

@Test func testUninstallScriptRemovesClaudeRegistrationAndKeepsManualScripterReminder() throws {
    let script = try scriptContents("Scripts/uninstall.sh")

    #expect(script.contains("claude mcp remove logic-pro"))
    #expect(script.contains("Remove Scripter MIDI FX"))
    #expect(script.contains("APPROVAL_STORE"))
    #expect(script.contains("Removed operator approvals"))
}
