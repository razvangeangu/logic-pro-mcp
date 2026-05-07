# T3 — `MarkerState.positionSource` Enum + Codable Backward Compat

**Status**: Todo
**Size**: S
**의존성**: 없음 (T1/T2와 병렬 가능)
**PRD**: AC-3.1, AC-3.4, AC-3.5, AC-6.4

## 목표

`MarkerState` 에 `positionSource: PositionSource` enum field 추가. Codable backward compat — 기존 v3.1.x cache snapshot 디코딩 시 missing field → `.unknown`.

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
    // v3.1.x cache snapshot — positionSource field 없음
    let legacyJSON = #"{"id":0,"name":"VOCALS","position":"146.4.4.240"}"#.data(using: .utf8)!
    let decoded = try JSONDecoder().decode(MarkerState.self, from: legacyJSON)
    #expect(decoded.positionSource == .unknown)
    // 기존 field 동작 유지
    #expect(decoded.id == 0)
    #expect(decoded.name == "VOCALS")
    #expect(decoded.position == "146.4.4.240")
}

@Test
func markerState_codableLegacyArray_decodes() throws {
    // v3.1.x cache snapshot이 marker array 일 때 — 가장 일반적
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

**Red 확인**: 기존 `MarkerState` 에 `positionSource` 없음 → 컴파일 에러 → Red.

## Green Phase 구현

`Sources/LogicProMCP/State/StateModels.swift`:

```swift
/// Marker position의 출처 — `.parser` 는 canonical (parseMarkerListPosition 성공),
/// `.fallback` 은 manufactured (`\(index+1).1.1.1`), `.unknown` 은 v3.1.x 이하의
/// legacy cache snapshot (provenance 정보 없음). 신규 marker는 항상 `.parser`
/// 또는 `.fallback` 으로 명시 — `.unknown` 은 decode 결과로만 발생.
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

    // Codable backward compat — v3.1.x snapshot은 positionSource field 없음 → .unknown
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

JSON snake_case 변환은 `JSONEncoder.keyEncodingStrategy = .convertToSnakeCase` 필요 시 ResourceHandlers에서 적용. 기존 `encodeJSON` 헬퍼 패턴 따름.

## Refactor Phase

- `positionSource` 기본값 init parameter — 기존 호출 site (테스트 등)가 변경 없이 컴파일되도록
- 한글 주석 (enum 의미 + Codable backward compat WHY)
- AC-4.2 grep TODO/FIXME 0건

## Acceptance Criteria

- **AC-T3.1**: `PositionSource` enum 3 cases (parser/fallback/unknown)
- **AC-T3.2**: `MarkerState.positionSource` field — default `.parser` (init), Codable missing → `.unknown` (decode)
- **AC-T3.3**: 4 Codable round-trip + legacy snapshot tests PASS
- **AC-T3.4**: 기존 1064 tests 회귀 0건 — `MarkerState` 사용 site 컴파일 OK (기본값 default arg로 자동)
- **AC-T3.5**: 한글 주석, 신규 TODO 0건
- **AC-T3.6**: SOLID — enum 자체는 immutable value type, MarkerState 에만 추가

## Out of Scope

- caller fallback site에서 `.fallback` 마킹 = T4
- resource envelope surface = T5
- goto_marker uncertainty extras = T6
