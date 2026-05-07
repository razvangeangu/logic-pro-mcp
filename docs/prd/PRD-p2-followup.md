# PRD — P2 후속: parameterized + AX assertion 소급 + HC addExtras

**Status**: Draft (v0.3 — boomer round 2 정리)
**Size**: M
**Owner**: Isaac
**Started**: 2026-05-07
**Driving**: v3.2.0 ship 후 4-agent 리뷰의 P2 항목 수렴 (production code change 최소, 테스트 품질 + 추상화 위생).

---

## 1. Goal

v3.2.0 release 직후 production code 회귀 위험 0의 정리 작업 3건 (boomer P2-2 round 1: `mergeMarkerUncertainty` parameterized 통합 drop — 검증 field 다름 → split 유지):

1. `markerState_codableRoundTrip_*` 3 case → parameterized 통합 (균질 round-trip 검증)
2. AX walker 통합 테스트 (`AXMarkers12MarkerListTests`) 7개에 `positionSource` assertion 소급
3. `HonestContract.addExtras(_:)` 첫급 API 추가 — `mergeMarkerUncertainty` 의 `JSONSerialization` 우회를 HC 계층으로 끌어올려 추상화 위생 향상

## 2. Non-Goals

- HC contract semantics 변경 — `success`/`verified`/`reason`/`error` 필드 동작 동일.
- production code behavior 변경 — `goto_marker` 응답 schema 동일 (`marker_position_uncertain` + `marker_position_source` 그대로). 내부 구현 경로만 HC API 통과.
- AX walker 동작 변경 — 통합 테스트 assertion 추가만.
- 새 wire schema field 추가 — out of scope.

## 3. Background

### 3.1 v3.2.0 4-agent 리뷰 P2 잔여

직전 두 차례 /simplify pass + Phase G review 에서 다음 P2 들이 후속 가치로 분류됨:

| # | 항목 | 출처 |
|---|------|------|
| 1 | `mergeMarkerUncertainty` 4 case parameterized | Tester P2-1 (1차) |
| 2 | Codable round-trip 3 case parameterized | Tester P2-1 (1차) |
| 3 | AX walker 통합 테스트 `positionSource` 소급 | Tester P2-2 (1차) |
| 4 | HC `addExtras(_:)` helper | Reuse Agent R1 (1차) + Quality Agent Q1 (1차) — leaky abstraction |

### 3.2 현재 mergeMarkerUncertainty 구조

`Sources/LogicProMCP/Dispatchers/NavigateDispatcher.swift:177-195` — `JSONSerialization` 으로 raw JSON 을 parse → mutate → re-encode. HC envelope 추상화 우회 (HC 본체에는 extras merge primitive 없음 — 각 state encoder 가 인라인 dict copy).

### 3.3 HC State A/B/C encoder 패턴 (HonestContract.swift:73-105)

각 encoder 가 동일 패턴:
```swift
var dict: [String: Any] = [...top-level keys...]
for (k, v) in extras { dict[k] = v }
return jsonString(dict)
```

extras merge 가 이미 HC 내부에 있음 — encoding 시점에. 그러나 **post-encode merge** API 없음 → mergeMarkerUncertainty 가 HC 외부에서 JSONSerialization 으로 우회.

### 3.4 AX walker 통합 테스트 현재

`AXMarkers12MarkerListTests.swift` 의 `enumerateMarkers_*` 테스트 (5+ 건) 가 `markers[0].name`, `markers[0].position` assert 하지만 **`positionSource` 검증은 없음**. v3.2 provenance 계약을 통합 layer 에서 보호 안 함 — 단위 테스트로만 보호.

## 4. Functional Requirements

### 4.1 Parameterized 통합 (FR-1) — scope 축소 (boomer round 1 P2-2)

- **AC-1.1** [DROPPED in v0.2]: `mergeMarkerUncertainty_*` 4 case parameterized 통합 — boomer P2-2 + Reuse Agent 직전 review 일관: 4 case가 검증 field/semantics 가 서로 달라 (`!contains`, `contains "success":true`, `contains "verified":false`, exact equality) 단일 `arguments` 매트릭스로 묶으면 가독성 해침. **현행 4 개별 함수 유지**.
- **AC-1.2**: `markerState_codableRoundTrip_*` 3 개별 → 단일 `@Test(arguments: [PositionSource.parser, .fallback, .unknown])`. 모두 동일 round-trip + `positionSource == ` enum case 검증으로 균질 → 통합 자연스러움. 신규 enum case 추가 시 테스트 자동 확장.
- **AC-1.3**: 통합 후 case 별 enum 값을 `#expect` 메시지에 명시 — 실패 진단성 보존.

### 4.2 AX walker assertion 소급 (FR-2 — boomer round 1 P1)

`AXMarkers12MarkerListTests.swift` 의 다음 marker-producing `enumerateMarkers_*` 함수에 `markers[i].positionSource` assertion 명시 (line 번호 boomer 직접 식별):

| 함수 (line) | 마커 source | 기대 `positionSource` |
|------------|-----------|----------------------|
| `enumerateMarkers_logic122_markerListWindow_open_returnsMarkers` (L85) | parser 성공 (Logic 12.2 list 윈도우) | `.parser` |
| `enumerateMarkers_listWindow_closed_fallsThroughToRulerStrategy` (L127) | parser 성공 (ruler fallback) | `.parser` |
| `enumerateMarkers_listAndRulerBothPresent_listWins` (L220) | parser 성공 (list 우선) | `.parser` |
| `enumerateMarkers_malformedRow_skipsRowKeepsValid` (L252) | parser 성공 — malformed row 는 skip 됨, 살아남은 row 만 검증 | `.parser` |
| `enumerateMarkers_unparseablePosition_usesIndexFallback` (L317) | parser 실패 → caller fallback | `.fallback` |
| `enumerateMarkers_trailingDotPosition_canonicalizes` (L341) | parser 성공 (영문 12.2 trailing dot strip) | `.parser` |
| `enumerateMarkers_koreanWholeBarPosition_canonicalizes` (L361) | parser 성공 (한글 whole-bar) | `.parser` |

- **AC-2.1**: 위 7 함수 모두에 `markers[*].positionSource` assertion 명시 추가.
- **AC-2.2**: 기존 assertion (`name`, `position`) 변경 0 — 라인 추가만.
- **AC-2.3**: Multi-marker 시나리오 (예: `_listAndRulerBothPresent_listWins` 의 list-소스 marker / `_malformedRow_skipsRowKeepsValid` 의 살아남은 valid row) — 검증 대상 모든 marker 검증.

### 4.3 HC addExtras helper (FR-3 — boomer round 1 P2-1)

- **AC-3.1**: `HonestContract` 에 `static func addExtras(_ extras: [String: Any], into rawJSON: String) -> String` 추가 (boomer P2-1 fix: `requireSuccess: Bool = true` flag 제거. YAGNI — 현재 caller 는 1 (mergeMarkerUncertainty), 정책 단일 (State C skip). 두 번째 caller 출현 시 별도 method 분리). 의미:
  - rawJSON 을 JSON object 로 parse
  - parse 실패 → 원본 그대로 반환 (defensive — production 정상 경로에서는 발생 안 함)
  - `(parsed["success"] as? Bool) == false` → 원본 그대로 반환 (HC State C 보존 — error 응답에 caller-side extras 추가 금지)
  - 위 가드 통과 시 top-level keys merge → re-encode (sortedKeys)
- **AC-3.2**: `NavigateDispatcher.mergeMarkerUncertainty(into:source:)` 가 `addExtras` 위임:
  ```swift
  static func mergeMarkerUncertainty(into rawJSON: String, source: PositionSource) -> String {
      HonestContract.addExtras([
          "marker_position_uncertain": true,
          "marker_position_source": source.rawValue,
      ], into: rawJSON)
  }
  ```
- **AC-3.3**: 외부 클라이언트 응답 동일 — JSON output byte-identical (sortedKeys + 동일 key set).
- **AC-3.4**: 기존 `mergeMarkerUncertainty_*` 4 개별 테스트 (parameterized 통합 drop, split 유지) 회귀 0.
- **AC-3.5**: HC 자체 테스트 추가 — `addExtras` 의 4 시나리오 (State A merge / State B merge + reason 보존 / State C skip / invalid JSON).

### 4.4 코드 규약 (FR-4)

- **AC-4.1**: 신규/수정 코드 한글 주석만 (영어 주석 추가 금지).
- **AC-4.2**: 신규 TODO/FIXME/XXX 0건.
- **AC-4.3**: `HonestContract.addExtras` 본문 ≤ 25 lines.
- **AC-4.4**: SOLID/SRP — `addExtras` 는 generic post-encode merge primitive (positionSource 등 도메인 지식 0).

## 5. Implementation Plan (티켓 분해 v0.2)

| # | 제목 | Size | 의존성 |
|---|------|------|--------|
| T1 | Codable round-trip 3 case → parameterized | S | — |
| T2 | AX walker 7 통합 테스트 positionSource assertion 소급 | S | — |
| T3 | HC.addExtras helper + NavigateDispatcher 위임 + HC tests | S | — |

> 각 ticket independent (병렬 가능). 의존성 없음. v0.1 의 T2 (mergeMarkerUncertainty parameterized) 는 v0.2 에서 drop — boomer P2-2.

## 6. Risks & Mitigations

| Risk | Severity | Mitigation |
|------|---------|-----------|
| Parameterized 통합 시 테스트 의도 모호 | Low | 각 row 에 명시적 expectation tuple 사용 + 테스트 description 에 시나리오 명시 |
| `addExtras` 도입이 mergeMarkerUncertainty 의 sortedKeys 동작 변경 | Low | `JSONSerialization.WritingOptions` `[.sortedKeys]` 동일 옵션 유지 + JSON output byte equality 테스트 |
| HC 본체 변경이 다른 dispatcher 영향 | Low | `addExtras` 신규 함수만, 기존 `encodeStateA/B/C` 시그니처 무변경 |
| AX walker 통합 테스트 assertion 추가가 기존 fixture 깨짐 | Low | 기존 `position`/`name` assertion 옆에 라인만 추가 (구조 무변경) |

## 7. Tests

- **AC-7.1**: `swift test --no-parallel` → 1081 PASS 유지 (또는 +N — addExtras 테스트 시나리오 4건 추가).
- **AC-7.2**: `swift build -c release` clean (0 warnings).
- **AC-7.3**: 통합 테스트 5+ 건의 `positionSource` 검증으로 v3.2 provenance 계약 보호 강화.

## 8. Success Metrics

- Tests: 1081 → 1081-1085 (parameterized 변환은 invocation count 동일 또는 변동 무시 + AX assertion 라인 추가는 test count 변화 0 + HC.addExtras 테스트 +4)
- Build clean
- `mergeMarkerUncertainty` 본문 ≤ 5 lines (HC 위임)
- `HonestContract.addExtras` 본문 ≤ 25 lines

## Version History

- **v0.1** (2026-05-07): 초안.
- **v0.2** (2026-05-07): Boomer round 1 통합 — P1 (AC-2.1 explicit 7 함수 + line + 기대값 표) + P2-1 (`addExtras` `requireSuccess` flag 제거 — YAGNI) + P2-2 (mergeMarkerUncertainty parameterized 통합 drop — 검증 field 다름 → split 유지). 티켓 4 → 3.
- **v0.3** (2026-05-07): Boomer round 2 정리 — Goal §1 stale 4건 → 3건 동기화 / AC-3.4 wording (parameterized 후 → split 유지) / AC-2.1 표 실제 test 함수명으로 정정 (boomer codex grep 검증).
