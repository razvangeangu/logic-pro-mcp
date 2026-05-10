# T5 — `logic://markers` Resource Envelope `position_source` + Derived `is_canonical`

**Status**: Todo
**Size**: S
**Depends on**: T3
**PRD**: AC-3.2, AC-3.3
**Boomer Phase E P2-1 fix**: Use existing `encodeJSON<T: Encodable>` + `jsonStringEscape` (JSONHelper.swift). Manual string concatenation prohibited — `Encodable` DTO recommended.

## Goal

Include per-marker `position_source` (snake_case) + derived `is_canonical: Bool` in the `logic://markers` JSON response. `is_canonical = position_source == "parser"`.

## TDD Red Phase

```swift
@Test
func readMarkers_envelope_includesPositionSource() async throws {
    let cache = StateCache()
    await cache.updateMarkers([
        MarkerState(id: 0, name: "A", position: "1.1.1.1", positionSource: .parser),
        MarkerState(id: 1, name: "B", position: "2.1.1.1", positionSource: .fallback),
    ])
    let result = try await ResourceHandlers.readMarkers(cache: cache, uri: "logic://markers")
    let json = result.contents.first.flatMap { contentText($0) } ?? ""

    // parser case
    #expect(json.contains("\"position_source\":\"parser\""))
    #expect(json.contains("\"is_canonical\":true"))

    // fallback case
    #expect(json.contains("\"position_source\":\"fallback\""))
    #expect(json.contains("\"is_canonical\":false"))
}

@Test
func readMarkers_envelope_legacyUnknown_isCanonicalFalse() async throws {
    // .unknown from legacy snapshot decode — is_canonical false
    let cache = StateCache()
    await cache.updateMarkers([
        MarkerState(id: 0, name: "Legacy", position: "1.1.1.1", positionSource: .unknown),
    ])
    let result = try await ResourceHandlers.readMarkers(cache: cache, uri: "logic://markers")
    let json = result.contents.first.flatMap { contentText($0) } ?? ""

    #expect(json.contains("\"position_source\":\"unknown\""))
    #expect(json.contains("\"is_canonical\":false"))
}
```

**Red confirmation**: Current `encodeJSON([MarkerState])` outputs Swift camelCase (`positionSource`) or (depending on Codable default behavior) omits it → assertion FAIL.

## Green Phase Implementation (Encodable DTO + existing helper)

`Sources/LogicProMCP/Resources/ResourceHandlers.swift` `readMarkers`:

```swift
/// v3.2 — wire schema includes position_source + derived is_canonical per marker.
/// Separate DTO reason: MarkerState is domain model (positionSource camelCase),
/// wire uses snake_case + derived field. SRP — two responsibilities separated.
private struct MarkerWireDTO: Encodable {
    let id: Int
    let name: String
    let position: String
    let position_source: String
    let is_canonical: Bool
}

private static func readMarkers(cache: StateCache, uri: String) async throws -> ReadResource.Result {
    let markers = await cache.getMarkers()
    let fetchedAt = await cache.getMarkersFetchedAt()
    let axOccluded = await cache.getAXOccluded()

    let dtos = markers.map { m in
        MarkerWireDTO(
            id: m.id,
            name: m.name,
            position: m.position,
            position_source: m.positionSource.rawValue,
            is_canonical: m.positionSource == .parser
        )
    }
    let body = encodeJSON(dtos)  // existing helper (JSONHelper.swift:99)

    let source: String
    if !markers.isEmpty {
        source = "ax_live"
    } else if fetchedAt > .distantPast {
        source = axOccluded ? "cache" : "ax_live"
    } else {
        source = "default"
    }
    let envelope = wrapWithCacheEnvelope(
        bodyJSON: body, fetchedAt: fetchedAt, axOccluded: axOccluded,
        extras: ["source": source]
    )
    return ReadResource.Result(
        contents: [.text(envelope, uri: uri, mimeType: "application/json")]
    )
}
```

DTO field `position_source` snake_case naming → serialized as-is with JSONEncoder default behavior (no `keyEncodingStrategy`). No CodingKeys override needed.

Existing string-escape safety: `JSONEncoder` handles standard escaping (control chars + quote + backslash).

## Refactor Phase

- Korean comments (WHY: SRP — domain model vs wire schema separation)
- Use existing `encodeJSON<T: Encodable>` (JSONHelper.swift:99) + JSONEncoder standard escape — Boomer P2-1 fix: manual string concat prohibited
- `MarkerWireDTO` is `private` nested type — not exposed externally

## Acceptance Criteria

- **AC-T5.1**: Response JSON includes per-marker `position_source: "parser"|"fallback"|"unknown"`
- **AC-T5.2**: Response JSON includes per-marker `is_canonical: true|false` (derived)
- **AC-T5.3**: `is_canonical: true` only when `position_source == "parser"`
- **AC-T5.4**: 3 integration tests (parser / fallback / unknown) PASS
- **AC-T5.5**: Existing marker resource tests: 0 regressions (envelope shape unchanged)
- **AC-T5.6**: Korean comments, no new TODOs
- **AC-T5.7**: JSONEncoder standard escape — `"`, `\`, control chars safe (no custom helper needed)
- **AC-T5.8**: `MarkerWireDTO` not split to separate file (private nested in ResourceHandlers — SRP within file scope)

## Out of Scope

- goto_marker uncertainty extras = T6
- docs/API.md update = T8
