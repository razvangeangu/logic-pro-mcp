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

    // Dual-mode release: stable tags require notarization; prerelease tags may
    // use ADHOC for release-candidate validation.
    #expect(workflow.contains("Detect release mode"))
    #expect(workflow.contains("mode=notarized"))
    #expect(workflow.contains("mode=adhoc"))
    #expect(workflow.contains("Stable ADHOC releases are not permitted"))
    #expect(!workflow.contains("ALLOW_ADHOC_STABLE"))
    #expect(workflow.contains("Validate notarization secrets"))
    #expect(workflow.contains("is required for a notarized release build"))
    #expect(workflow.contains("Codesign binary (Developer ID)"))
    #expect(workflow.contains("Codesign binary (ADHOC)"))
    #expect(workflow.contains("codesign --force --sign - LogicProMCP"))
    #expect(workflow.contains("RELEASE-METADATA.json"))
    #expect(workflow.contains("validate-install"))
    #expect(workflow.contains("macos-15"))
    #expect(workflow.contains("macos-13"))
    #expect(workflow.contains("LOGIC_PRO_MCP_INSTALL_DIR"))
}

@Test func testLocalReleaseScriptIsPrereleaseOnlyAndFailClosedOnRemoteCheck() throws {
    let script = try scriptContents("Scripts/release.sh")

    #expect(script.contains("refuses stable tags"))
    #expect(script.contains("There is intentionally no override"))
    #expect(!script.contains("LOGIC_PRO_MCP_ALLOW_ADHOC_STABLE"))
    #expect(script.contains("RELEASE_FLAGS=\"--prerelease\""))
    #expect(script.contains("could not verify remote tag availability"))
    #expect(script.contains("Refusing to continue because publishing could race"))
}

@Test func testUninstallScriptRemovesClaudeRegistrationAndKeepsManualScripterReminder() throws {
    let script = try scriptContents("Scripts/uninstall.sh")

    #expect(script.contains("claude mcp remove logic-pro"))
    #expect(script.contains("Remove Scripter MIDI FX"))
    #expect(script.contains("APPROVAL_STORE"))
    #expect(script.contains("Removed operator approvals"))
}
