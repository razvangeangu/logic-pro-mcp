import Testing
import Foundation
@testable import LogicProMCP

// v3.2 — Marker provenance 검증.
// PositionSource enum + Codable backward compat + resource envelope
// (position_source / is_canonical) + goto_marker HC top-level uncertainty merge.

// MARK: - MarkerState Codable round-trip

@Test("MarkerState Codable round-trip — .parser")
func markerState_codableRoundTrip_parser() throws {
    let original = MarkerState(
        id: 0, name: "VOCALS", position: "146.4.4.240", positionSource: .parser
    )
    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(MarkerState.self, from: data)
    #expect(decoded == original)
    #expect(decoded.positionSource == .parser)
}

@Test("MarkerState Codable round-trip — .fallback")
func markerState_codableRoundTrip_fallback() throws {
    let original = MarkerState(
        id: 1, name: "Section A", position: "2.1.1.1", positionSource: .fallback
    )
    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(MarkerState.self, from: data)
    #expect(decoded.positionSource == .fallback)
}

@Test("MarkerState Codable round-trip — .unknown")
func markerState_codableRoundTrip_unknown() throws {
    let original = MarkerState(
        id: 2, name: "Legacy", position: "1.1.1.1", positionSource: .unknown
    )
    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(MarkerState.self, from: data)
    #expect(decoded.positionSource == .unknown)
}

// v3.1.x cache snapshot 디코딩 — positionSource field 없음 → .unknown
// (Boomer P1-2: false provenance 차단).
@Test("MarkerState legacy snapshot decode → .unknown")
func markerState_legacySnapshot_decodesAsUnknown() throws {
    let legacyJSON = #"{"id":0,"name":"VOCALS","position":"146.4.4.240"}"#
        .data(using: .utf8)!
    let decoded = try JSONDecoder().decode(MarkerState.self, from: legacyJSON)
    #expect(decoded.positionSource == .unknown)
    #expect(decoded.id == 0)
    #expect(decoded.name == "VOCALS")
    #expect(decoded.position == "146.4.4.240")
}

@Test("MarkerState legacy array decode — 모두 .unknown")
func markerState_legacyArray_decodesAsUnknown() throws {
    let legacyJSON = #"""
    [
      {"id":0,"name":"A","position":"1.1.1.1"},
      {"id":1,"name":"B","position":"2.1.1.1"}
    ]
    """#.data(using: .utf8)!
    let decoded = try JSONDecoder().decode([MarkerState].self, from: legacyJSON)
    #expect(decoded.count == 2)
    #expect(decoded.allSatisfy { $0.positionSource == .unknown })
}

// MARK: - PositionSource enum

@Test("PositionSource rawValue 안정성 (wire schema 보장)")
func positionSource_rawValueStability() {
    #expect(PositionSource.parser.rawValue == "parser")
    #expect(PositionSource.fallback.rawValue == "fallback")
    #expect(PositionSource.unknown.rawValue == "unknown")
}

// MARK: - goto_marker uncertainty merge (HC top-level)

@Test("mergeMarkerUncertainty: HC State A → top-level extras 추가")
func mergeMarkerUncertainty_stateA_addsTopLevelExtras() {
    let raw = #"{"requested":"1.1.1.1","success":true,"verified":true}"#
    let merged = NavigateDispatcher.mergeMarkerUncertainty(
        into: raw, source: .fallback
    )
    #expect(merged.contains("\"marker_position_uncertain\":true"))
    #expect(merged.contains("\"marker_position_source\":\"fallback\""))
    #expect(merged.contains("\"success\":true"))
}

@Test("mergeMarkerUncertainty: HC State B → 보존 + extras 추가")
func mergeMarkerUncertainty_stateB_preservesReason() {
    let raw = #"{"reason":"readback_unavailable","success":true,"verified":false}"#
    let merged = NavigateDispatcher.mergeMarkerUncertainty(
        into: raw, source: .unknown
    )
    #expect(merged.contains("\"marker_position_uncertain\":true"))
    #expect(merged.contains("\"marker_position_source\":\"unknown\""))
    #expect(merged.contains("\"reason\":\"readback_unavailable\""))
    #expect(merged.contains("\"verified\":false"))
}

@Test("mergeMarkerUncertainty: HC State C (success:false) → merge skip")
func mergeMarkerUncertainty_stateC_skipsMerge() {
    let raw = #"{"error":"ax_write_failed","success":false}"#
    let merged = NavigateDispatcher.mergeMarkerUncertainty(
        into: raw, source: .fallback
    )
    // State C 보존 — uncertainty merge 안 함
    #expect(!merged.contains("marker_position_uncertain"))
    #expect(merged.contains("\"success\":false"))
    #expect(merged.contains("\"error\":\"ax_write_failed\""))
}

@Test("mergeMarkerUncertainty: invalid JSON → 원본 그대로")
func mergeMarkerUncertainty_invalidJSON_returnsRaw() {
    let raw = "not json"
    let merged = NavigateDispatcher.mergeMarkerUncertainty(
        into: raw, source: .fallback
    )
    #expect(merged == raw)
}
