import Foundation
import Testing
@testable import LogicProMCP

// T3/T4 — verified-plugin identity + capability resolution (R5/R6, AC10/AC11).
// Deterministic; no live AX.

// MARK: - Plugin identity alias resolution (AC11)

@Test func testCanonicalPluginIDResolvesDisplayNameAndSuffix() {
    #expect(VerifiedPluginCatalog.canonicalPluginID(from: "Gain") == "logic.stock.effect.gain")
    #expect(VerifiedPluginCatalog.canonicalPluginID(from: "gain") == "logic.stock.effect.gain")
    #expect(VerifiedPluginCatalog.canonicalPluginID(from: "  GAIN  ") == "logic.stock.effect.gain")
    #expect(VerifiedPluginCatalog.canonicalPluginID(from: "logic.stock.effect.gain") == "logic.stock.effect.gain")
    #expect(VerifiedPluginCatalog.canonicalPluginID(from: "Channel EQ") == "logic.stock.effect.channel_eq")
    #expect(VerifiedPluginCatalog.canonicalPluginID(from: "Compressor") == "logic.stock.effect.compressor")
    #expect(VerifiedPluginCatalog.canonicalPluginID(from: "Noise Gate") == "logic.stock.effect.noise_gate")
}

@Test func testCanonicalPluginIDRejectsUnbackedIdentity() {
    // AC11: an ungrounded com.apple.logic.* id has no alias mapping → refuse.
    #expect(VerifiedPluginCatalog.canonicalPluginID(from: "com.apple.logic.gain") == nil)
    #expect(VerifiedPluginCatalog.canonicalPluginID(from: "") == nil)
    #expect(VerifiedPluginCatalog.canonicalPluginID(from: "Definitely Not A Plugin") == nil)
}

// MARK: - Parameter key alias resolution (R5: gain → gain_db)

@Test func testCanonicalParamKeyMapsGainAlias() {
    let gain = "logic.stock.effect.gain"
    #expect(VerifiedPluginCatalog.canonicalParamKey(pluginID: gain, alias: "gain_db") == "gain")
    #expect(VerifiedPluginCatalog.canonicalParamKey(pluginID: gain, alias: "gain") == "gain")
    #expect(VerifiedPluginCatalog.canonicalParamKey(pluginID: gain, alias: "GAIN_DB") == "gain")
    #expect(VerifiedPluginCatalog.canonicalParamKey(pluginID: gain, alias: "unknown_param") == nil)
}

// MARK: - Observed-name → plugin_id for get_inventory

@Test func testObservedNameMapsToCanonicalID() {
    #expect(VerifiedPluginCatalog.pluginID(forObservedName: "Gain") == "logic.stock.effect.gain")
    #expect(VerifiedPluginCatalog.pluginID(forObservedName: "Noise Gate") == "logic.stock.effect.noise_gate")
    // A non-allowlisted (or third-party) plugin name does not resolve.
    #expect(VerifiedPluginCatalog.pluginID(forObservedName: "Drum Machine Designer") == nil)
}

// MARK: - Capability preflight (AC10) — Gain is currently unsupported

@Test func testGainParamCapabilityIsUnsupportedUntilEvidence() {
    // Gain's catalog param has writeMethod:nil, readbackMethod:nil (.inferred),
    // so preflight must report .unsupported → State C unsupported_param_readback.
    let cap = VerifiedPluginCatalog.paramCapability(pluginID: "logic.stock.effect.gain", paramKey: "gain")
    #expect(cap == .unsupported)
}

@Test func testUnknownParamCapabilityIsUnknownParameter() {
    #expect(
        VerifiedPluginCatalog.paramCapability(pluginID: "logic.stock.effect.gain", paramKey: "nope")
            == .unknownParameter
    )
    // An unknown compressor param is still unknown; `threshold` itself is now
    // writeReadback (T5) — see testCompressorThresholdCapabilityIsWriteReadback.
    #expect(
        VerifiedPluginCatalog.paramCapability(pluginID: "logic.stock.effect.compressor", paramKey: "ratio")
            == .unknownParameter
    )
}

// MARK: - T5: Compressor threshold is the first verified-writable parameter

@Test func testCompressorThresholdCapabilityIsWriteReadback() {
    // T0 spike filled the AX write/readback methods, so preflight now admits a
    // verified write for this one parameter.
    #expect(
        VerifiedPluginCatalog.paramCapability(pluginID: "logic.stock.effect.compressor", paramKey: "threshold")
            == .writeReadback
    )
    #expect(VerifiedPluginCatalog.canonicalParamKey(pluginID: "logic.stock.effect.compressor", alias: "threshold") == "threshold")
}

@Test func testCompressorThresholdUnitRangeToleranceAndAXDescription() {
    let id = "logic.stock.effect.compressor"
    #expect(VerifiedPluginCatalog.paramUnit(pluginID: id, paramKey: "threshold") == "normalized")
    let range = VerifiedPluginCatalog.paramRange(pluginID: id, paramKey: "threshold")
    #expect(range?.min == 0)
    #expect(range?.max == 100)
    #expect(VerifiedPluginCatalog.paramTolerance(pluginID: id, paramKey: "threshold") == 1.0)
    // AX identification is by AXDescription only (AXIdentifier is unstable).
    #expect(VerifiedPluginCatalog.paramAXDescription(pluginID: id, paramKey: "threshold") == "Threshold")
}

// MARK: - Unit + range exposure (R8)

@Test func testGainParamUnitAndRange() {
    #expect(VerifiedPluginCatalog.paramUnit(pluginID: "logic.stock.effect.gain", paramKey: "gain") == "dB")
    let range = VerifiedPluginCatalog.paramRange(pluginID: "logic.stock.effect.gain", paramKey: "gain")
    #expect(range?.min == -96)
    #expect(range?.max == 24)
}
