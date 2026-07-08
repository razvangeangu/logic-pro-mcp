import AppKit
import Foundation
import Testing
@testable import LogicProMCP

@Test func logicProVariantPolicyUnknownBundleProcessNameIsHonest() {
    #expect(LogicProVariantPolicy.processName(forBundleID: "com.example.unknown") == "com.example.unknown")
    #expect(LogicProVariantPolicy.processName(forBundleID: "com.apple.logic10") == "Logic Pro")
}

@Test func logicProTargetKnownVariantsIncludeDesktopAndCreatorStudio() {
    #expect(LogicProTarget.knownBundleIDs.contains("com.apple.logic10"))
    #expect(LogicProTarget.knownBundleIDs.contains("com.apple.mobilelogic"))
    #expect(LogicProTarget.desktop.variant == .desktop)
    #expect(LogicProTarget.creatorStudio.variant == .creatorStudio)
    #expect(LogicProTarget.creatorStudio.processName == "Logic Pro Creator Studio")
    #expect(LogicProTarget.creatorStudio.variant.defaultInstallPath == "/Applications/Logic Pro Creator Studio.app")
    #expect(LogicProTarget.desktop.processName == "Logic Pro")
}

@Test func logicProTargetManifestMetadataMatchesSwiftVariants() throws {
    let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let manifestURL = repoRoot.appendingPathComponent("manifest.json")
    let data = try Data(contentsOf: manifestURL)
    let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    let variants = object?["supported_logic_pro_variants"] as? [[String: Any]]
    let manifestByName = Dictionary(uniqueKeysWithValues: (variants ?? []).compactMap { entry -> (String, [String: Any])? in
        guard let name = entry["name"] as? String else { return nil }
        return (name, entry)
    })

    for variant in LogicProVariant.knownVariants {
        let manifestEntry = try #require(manifestByName[variant.rawValue])
        #expect(manifestEntry["bundle_id"] as? String == variant.bundleID)
        #expect(manifestEntry["process_name"] as? String == variant.processName)
        #expect(manifestEntry["default_install_path"] as? String == variant.defaultInstallPath)
    }
}

@Test func logicProTargetKnownBundleIDsMatchManifestOrder() throws {
    let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let manifestURL = repoRoot.appendingPathComponent("manifest.json")
    let data = try Data(contentsOf: manifestURL)
    let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    let variants = object?["supported_logic_pro_variants"] as? [[String: Any]]
    let manifestBundleIDs = variants?.compactMap { $0["bundle_id"] as? String }
    #expect(manifestBundleIDs == LogicProTarget.knownBundleIDs)
    #expect(LogicProTarget.knownBundleIDs.first == "com.apple.logic10")
}

@Test func logicProTargetForcedBundleIDOverridesAutoDetect() {
    let runtime = LogicProTarget.Runtime(
        forcedBundleID: { "com.apple.mobilelogic" },
        frontmostBundleID: { "com.apple.logic10" },
        runningApplications: { _ in [] },
        installedApplicationURL: { _ in nil }
    )
    LogicProTarget.invalidateCache()
    let target = LogicProTarget.resolveUncached(runtime: runtime)
    #expect(target.bundleID == "com.apple.mobilelogic")
    #expect(target.variant == .creatorStudio)
    #expect(target.processMetadataResolved)
}

@Test func logicProTargetPrefersFrontmostRunningVariant() {
    let runtime = LogicProTarget.Runtime(
        forcedBundleID: { nil },
        frontmostBundleID: { "com.apple.mobilelogic" },
        runningApplications: { bundleID in
            bundleID == "com.apple.mobilelogic" ? [NSRunningApplication()] : []
        },
        installedApplicationURL: { _ in nil }
    )
    LogicProTarget.invalidateCache()
    let target = LogicProTarget.resolveUncached(runtime: runtime)
    #expect(target.bundleID == "com.apple.mobilelogic")
}

@Test func logicProTargetFallsBackToDesktopInstallOrder() {
    let desktopURL = URL(fileURLWithPath: "/Applications/Logic Pro.app")
    let runtime = LogicProTarget.Runtime(
        forcedBundleID: { nil },
        frontmostBundleID: { nil },
        runningApplications: { _ in [] },
        installedApplicationURL: { bundleID in
            bundleID == LogicProVariant.desktop.bundleID ? desktopURL : nil
        }
    )
    LogicProTarget.invalidateCache()
    let target = LogicProTarget.resolveUncached(runtime: runtime)
    #expect(target.bundleID == "com.apple.logic10")
    #expect(target.variant == .desktop)
}

@Test func logicProTargetCreatorStudioInstallWhenDesktopMissing() {
    let creatorURL = URL(fileURLWithPath: "/Applications/Logic Pro Creator Studio.app")
    let runtime = LogicProTarget.Runtime(
        forcedBundleID: { nil },
        frontmostBundleID: { nil },
        runningApplications: { _ in [] },
        installedApplicationURL: { bundleID in
            bundleID == LogicProVariant.creatorStudio.bundleID ? creatorURL : nil
        }
    )
    LogicProTarget.invalidateCache()
    let target = LogicProTarget.resolveUncached(runtime: runtime)
    #expect(target.bundleID == "com.apple.mobilelogic")
}

@Test func logicProTargetAppleScriptTargetUsesBundleID() {
    let runtime = LogicProTarget.Runtime(
        forcedBundleID: { "com.apple.mobilelogic" },
        frontmostBundleID: { nil },
        runningApplications: { _ in [] },
        installedApplicationURL: { _ in nil }
    )
    LogicProTarget.invalidateCache()
    let appleScript = LogicProTarget.appleScriptTarget(runtime: runtime)
    #expect(appleScript.tellApplicationByBundleID == "tell application id \"com.apple.mobilelogic\"")
    #expect(appleScript.activateByBundleID == "tell application id \"com.apple.mobilelogic\" to activate")
    #expect(appleScript.systemEventsProcessTarget == "process \"Logic Pro Creator Studio\"")
}

@Test func logicProTargetForcedUnknownBundleDoesNotInventDesktopProcessName() {
    let runtime = LogicProTarget.Runtime(
        forcedBundleID: { "com.example.unknown" },
        frontmostBundleID: { nil },
        runningApplications: { _ in [] },
        installedApplicationURL: { _ in nil }
    )
    LogicProTarget.invalidateCache()
    let target = LogicProTarget.resolveUncached(runtime: runtime)
    #expect(target.bundleID == "com.example.unknown")
    #expect(target.processName == "com.example.unknown")
    #expect(!target.processMetadataResolved)
    #expect(target.variant == .unknown)
    #expect(target.variantLabel == "unknown_forced")
}

@Test func setupDoctorLogicVariantLabelMapsBundleIDs() {
    #expect(SetupDoctor.logicVariantLabel(for: "com.apple.logic10") == "desktop")
    #expect(SetupDoctor.logicVariantLabel(for: "com.apple.mobilelogic") == "creator_studio")
}

@Test func setupDoctorSupportedLogicAppsFiltersUnknownBundleIDs() {
    let apps = [
        SetupDoctor.LogicAppInfo(
            path: "/Applications/Logic Pro Creator Studio.app",
            version: "12.3",
            bundleID: "com.apple.mobilelogic",
            readable: true
        ),
        SetupDoctor.LogicAppInfo(
            path: "/Applications/Other.app",
            version: "1.0",
            bundleID: "com.example.other",
            readable: true
        ),
    ]
    let supported = SetupDoctor.supportedLogicApps(apps)
    #expect(supported.count == 1)
    #expect(supported[0].bundleID == "com.apple.mobilelogic")
}

@Test func setupDoctorInstallationCheckReportsCreatorStudioVariant() {
    let apps = [
        SetupDoctor.LogicAppInfo(
            path: "/Applications/Logic Pro Creator Studio.app",
            version: LogicProSupport.latestValidatedLogicVersion,
            bundleID: "com.apple.mobilelogic",
            readable: true
        ),
    ]
    let check = SetupDoctor.logicInstallationCheck(logicApps: apps)
    #expect(check.status == SetupDoctor.CheckStatus.pass)
    #expect(check.evidence["variant"] == "creator_studio")
    #expect(check.evidence["bundle_id"] == "com.apple.mobilelogic")
}

@Test func setupDoctorTCCRedactsMobileLogicAppleEvents() {
    let rows = [
        SetupDoctor.TCCRow(
            service: "kTCCServiceAppleEvents",
            client: "com.apple.Terminal",
            authValue: 0,
            indirectObjectIdentifier: "com.apple.mobilelogic"
        ),
    ]
    let findings = SetupDoctor.tccFindings(rows)
    #expect(findings.contains(where: { $0.contains("appleevents:mobilelogic") }))
}

@Test func processUtilsPreferredLogicPIDPrefersResolvedTarget() {
    LogicProTarget.invalidateCache()
    let runtime = LogicProTarget.Runtime(
        forcedBundleID: { "com.apple.mobilelogic" },
        frontmostBundleID: { nil },
        runningApplications: { _ in [] },
        installedApplicationURL: { _ in nil }
    )
    LogicProTarget.invalidateCache()
    _ = LogicProTarget.resolveUncached(runtime: runtime)

    // Without live NSRunningApplication bundle metadata, both PIDs are accepted;
    // ordering prefers the resolved target when bundle IDs are unavailable.
    let output = """
    100 Logic Pro
    200 Logic Pro
    """
    let pid = ProcessUtils.parseLogicProPID(fromProcessList: output)
    #expect(pid == 100)
}
