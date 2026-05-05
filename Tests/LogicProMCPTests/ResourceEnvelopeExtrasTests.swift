import Foundation
import Testing
@testable import LogicProMCP

// v3.1.8 (Issue #7) — extras parameter on wrapWithCacheEnvelope.
// When extras is nil/empty, envelope shape is byte-identical to v3.1.7.

private let stableDate = Date(timeIntervalSince1970: 1_700_000_000)

@Test
func extrasNil_envelopeMatchesV317Shape() {
    let result = ResourceHandlers.wrapWithCacheEnvelope(
        bodyJSON: "{\"x\":1}", fetchedAt: stableDate, axOccluded: false, extras: nil
    )
    // Shape (not byte) match — cache_age_sec is wall-clock derived; compare
    // by structure: same keys, no extras inserted, body intact.
    #expect(result.hasPrefix("{\"cache_age_sec\":"))
    #expect(result.contains("\"ax_occluded\":false,\"data\":{\"x\":1}"))
    #expect(!result.contains("\"source\""))
}

@Test
func extrasEmpty_treatedAsNil() {
    let withEmpty = ResourceHandlers.wrapWithCacheEnvelope(
        bodyJSON: "[]", fetchedAt: stableDate, extras: [:]
    )
    // No extras keys spliced in
    #expect(withEmpty.contains("\"ax_occluded\":false,\"data\":[]"))
    #expect(!withEmpty.contains("\"source\""))
}

@Test
func extrasWithSource_emitsKey() {
    let result = ResourceHandlers.wrapWithCacheEnvelope(
        bodyJSON: "{}", fetchedAt: stableDate, extras: ["source": "ax_live"]
    )
    #expect(result.contains("\"source\":\"ax_live\""))
}

@Test
func extrasMultipleKeys_sortedOrder() {
    let result = ResourceHandlers.wrapWithCacheEnvelope(
        bodyJSON: "{}", fetchedAt: stableDate,
        extras: ["zeta": 1, "alpha": 2, "mu": 3]
    )
    let alphaIdx = result.range(of: "\"alpha\"")?.lowerBound
    let muIdx = result.range(of: "\"mu\"")?.lowerBound
    let zetaIdx = result.range(of: "\"zeta\"")?.lowerBound
    #expect(alphaIdx != nil && muIdx != nil && zetaIdx != nil)
    #expect(alphaIdx! < muIdx!)
    #expect(muIdx! < zetaIdx!)
}

@Test
func extrasNumericValue_noQuotes() {
    let result = ResourceHandlers.wrapWithCacheEnvelope(
        bodyJSON: "{}", fetchedAt: stableDate,
        extras: ["last_saved_age_sec": 12.5]
    )
    #expect(result.contains("\"last_saved_age_sec\":12.5"))
}

@Test
func extrasBoolValue_noQuotes() {
    let result = ResourceHandlers.wrapWithCacheEnvelope(
        bodyJSON: "{}", fetchedAt: stableDate,
        extras: ["placeholder": true]
    )
    #expect(result.contains("\"placeholder\":true"))
}

@Test
func extrasNestedDict_emitted() {
    let result = ResourceHandlers.wrapWithCacheEnvelope(
        bodyJSON: "{}", fetchedAt: stableDate,
        extras: ["meta": ["a": 1]]
    )
    #expect(result.contains("\"meta\":{\"a\":1}"))
}

@Test
func extrasUnsupportedType_skipped() {
    // NSDate, raw classes — JSON-invalid → filtered out, no crash
    let result = ResourceHandlers.wrapWithCacheEnvelope(
        bodyJSON: "{}", fetchedAt: stableDate,
        extras: ["evil": Date(), "good": "ok"]
    )
    #expect(result.contains("\"good\":\"ok\""))
    #expect(!result.contains("\"evil\""))
}

@Test
func extrasEnvelopeStillContainsAxOccluded() {
    let result = ResourceHandlers.wrapWithCacheEnvelope(
        bodyJSON: "{}", fetchedAt: stableDate, axOccluded: true,
        extras: ["source": "cache"]
    )
    #expect(result.contains("\"ax_occluded\":true"))
    #expect(result.contains("\"source\":\"cache\""))
}
