# T3 — `MarkerState.positionSource` Enum + Codable Backward Compat

> Historical record (2026-06-09 docs refresh): latest production-readiness and live E2E evidence is in `README.md`, `CHANGELOG.md`, and `docs/live-verify-v3.4.6.md`; this file remains preserved implementation context.

**Status**: Todo
**Size**: S
**Depends on**: None (can run in parallel with T1/T2)
**PRD**: AC-3.1, AC-3.4, AC-3.5, AC-6.4

## Goal

Add `positionSource: PositionSource` enum field to `MarkerState`. Codable backward compat — existing v3.1.x cache snapshots with missing field decode as `.unknown`.

## TDD Red Phase

```swift
@Test
func markerState_codableRoundTrip_parser() throws {
    let original = MarkerState(id: 0, name: "VOCALS", position: "146.4.4.240", positionSource: .parser)
    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(MarkerState.self, from: data)
    #expect(decoded == original)
    #expect(decoded.positionSource == .parser)
}

@Test
func markerState_codableRoundTrip_fallback() throws {
    let original = MarkerState(id: 1, name: "Section A", position: "2.1.1.1", positionSource: .fallback)
    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(MarkerState.self, from: data)
    #expect(decoded.positionSource == .fallback)
}

@Test
func markerState_codableLegacySnapshot_missingField_decodesAsUnknown() throws {
    // v3.1.x cache snapshot — no positionSource field
    let legacyJSON = #"{"id":0,"name":"VOCALS","position":"146.4.4.240"}"#.data(using: .utf8)!
    let decoded = try JSONDecoder().decode(MarkerState.self, from: legacyJSON)
    #expect(decoded.positionSource == .unknown)
    // Existing field behavior preserved
    #expect(decoded.id == 0)
    #expect(decoded.name == "VOCALS")
    #expect(decoded.position == "146.4.4.240")
}

@Test
func markerState_codableLegacyArray_decodes() throws {
    // v3.1.x cache snapshot as marker array — most common case
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
```

**Red confirmation**: existing `MarkerState` has no `positionSource` → compile error → Red.

## Green Phase Implementation

`Sources/LogicProMCP/State/StateModels.swift`:

```swift
/// Provenance of a marker position — `.parser` is canonical (parseMarkerListPosition success),
/// `.fallback` is manufactured (`\(index+1).1.1.1`), `.unknown` is from
/// legacy v3.1.x cache snapshots (no provenance info). New markers are always `.parser`
/// or `.fallback` — `.unknown` appears only as a decode result.
enum PositionSource: String, Codable, Sendable, Equatable {
    case parser
    case fallback
    case unknown
}

/// Marker info.
struct MarkerState: Sendable, Codable, Identifiable, Equatable {
    let id: Int
    var name: String
    var position: String
    var positionSource: PositionSource

    init(id: Int, name: String, position: String, positionSource: PositionSource = .parser) {
        self.id = id
        self.name = name
        self.position = position
        self.positionSource = positionSource
    }

    // Codable backward compat — v3.1.x snapshots have no positionSource field → .unknown
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(Int.self, forKey: .id)
        self.name = try c.decode(String.self, forKey: .name)
        self.position = try c.decode(String.self, forKey: .position)
        self.positionSource = try c.decodeIfPresent(PositionSource.self, forKey: .positionSource)
            ?? .unknown
    }
}
```

JSON snake_case conversion applies `JSONEncoder.keyEncodingStrategy = .convertToSnakeCase` at ResourceHandlers if needed. Follows existing `encodeJSON` helper pattern.

## Refactor Phase

- `positionSource` default init parameter — allows existing call sites (tests etc.) to compile without changes
- Korean comments (enum semantics + Codable backward compat WHY)
- AC-4.2 grep TODO/FIXME 0

## Acceptance Criteria

- **AC-T3.1**: `PositionSource` enum with 3 cases (parser/fallback/unknown)
- **AC-T3.2**: `MarkerState.positionSource` field — default `.parser` (init), Codable missing → `.unknown` (decode)
- **AC-T3.3**: 4 Codable round-trip + legacy snapshot tests PASS
- **AC-T3.4**: Existing 1064 tests: 0 regressions — `MarkerState` usage sites compile OK (default arg auto-applies)
- **AC-T3.5**: Korean comments, no new TODOs
- **AC-T3.6**: SOLID — enum is immutable value type, added only to MarkerState

## Out of Scope

- Marking `.fallback` at caller fallback site = T4
- resource envelope surface = T5
- goto_marker uncertainty extras = T6
