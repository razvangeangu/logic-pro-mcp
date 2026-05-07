# T5 — `logic://markers` Resource Envelope `position_source` + Derived `is_canonical`

**Status**: Todo
**Size**: S
**의존성**: T3
**PRD**: AC-3.2, AC-3.3
**Boomer Phase E P2-1 fix**: 기존 `encodeJSON<T: Encodable>` + `jsonStringEscape` (JSONHelper.swift) 사용. 수동 string concat 금지 — `Encodable` DTO 권장.

## 목표

`logic://markers` JSON 응답에 marker 별 `position_source` (snake_case) + derived `is_canonical: Bool` 포함. `is_canonical = position_source == "parser"`.

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

    // parser 케이스
    #expect(json.contains("\"position_source\":\"parser\""))
    #expect(json.contains("\"is_canonical\":true"))

    // fallback 케이스
    #expect(json.contains("\"position_source\":\"fallback\""))
    #expect(json.contains("\"is_canonical\":false"))
}

@Test
func readMarkers_envelope_legacyUnknown_isCanonicalFalse() async throws {
    // legacy snapshot decode 결과로 .unknown — is_canonical false
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

**Red 확인**: 현재 `encodeJSON([MarkerState])` 는 Swift camelCase (`positionSource`) 또는 (Codable 기본 동작에 따라) 미포함 → assertion FAIL.

## Green Phase 구현 (Encodable DTO + 기존 helper)

`Sources/LogicProMCP/Resources/ResourceHandlers.swift` `readMarkers`:

```swift
/// v3.2 — wire schema에 position_source + derived is_canonical 포함.
/// 별도 DTO 사용 이유: MarkerState는 도메인 model (positionSource camelCase),
/// wire는 snake_case + derived field. SRP — 두 책임 분리.
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
    let body = encodeJSON(dtos)  // 기존 helper (JSONHelper.swift:99)

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

DTO field `position_source` snake_case naming → JSONEncoder 기본 동작 (no `keyEncodingStrategy`)으로 그대로 직렬화. CodingKeys override 불필요.

기존 string-escape 안전성: `JSONEncoder` 가 표준 escape 처리 (control char + quote + backslash).

## Refactor Phase

- 한글 주석 (WHY: SRP — 도메인 model vs wire schema 분리)
- 기존 `encodeJSON<T: Encodable>` (JSONHelper.swift:99) + JSONEncoder 표준 escape 사용 — boomer P2-1 fix: 수동 string concat 금지
- `MarkerWireDTO` 는 `private` nested type — 외부 노출 X

## Acceptance Criteria

- **AC-T5.1**: 응답 JSON에 marker 별 `position_source: "parser"|"fallback"|"unknown"` 포함
- **AC-T5.2**: 응답 JSON에 marker 별 `is_canonical: true|false` 포함 (derived)
- **AC-T5.3**: `position_source == "parser"` 일 때만 `is_canonical: true`
- **AC-T5.4**: 3 통합 테스트 (parser / fallback / unknown) PASS
- **AC-T5.5**: 기존 marker resource tests 회귀 0건 (envelope shape 동일)
- **AC-T5.6**: 한글 주석, 신규 TODO 0
- **AC-T5.7**: JSONEncoder 표준 escape — `"`, `\`, control chars 안전 (별도 helper 작성 X)
- **AC-T5.8**: `MarkerWireDTO` 별도 file 분리 안 함 (private nested in ResourceHandlers — SRP within file scope)

## Out of Scope

- goto_marker uncertainty extras = T6
- docs/API.md 갱신 = T8
