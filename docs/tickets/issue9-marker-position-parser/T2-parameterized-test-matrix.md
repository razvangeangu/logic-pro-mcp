# T2: parameterized test matrix (Swift Testing 25 cases)

**PRD Ref**: PRD-issue9 > §8.1
**Priority**: P0
**Size**: S (< 1h)
**Status**: Todo
**Depends On**: T1 (구현 후 Green 검증)

---

## 1. Objective
PRD §5의 14 edge cases + 1 통합 회귀를 Swift Testing parameterized로 컴팩트하게 작성. 기존 v3.1.10의 valid case `"17 2"` (lenient 2-component) → invalid로 명시 이동.

## 2. Acceptance Criteria
- [ ] AC-1: 신규 valid 8 cases + invalid 17 cases — 단 2개 `@Test(arguments:)`.
- [ ] AC-2: 기존 v3.1.10 테스트 `parseMarkerListPosition_validInputs` / `_invalidInputs` 삭제 — parameterized로 통합.
- [ ] AC-3: 한글 주석 (테스트 의도 + behavior change 명시).
- [ ] AC-4: 모든 25 cases가 T1 구현 후 PASS.
- [ ] AC-5: 라인 수 ≤ 50 (parameterized 압축).

## 3. TDD Spec (Red Phase)

### 3.1 Test 1: 유효 입력 (8 cases)
```swift
@Test("parseMarkerListPosition: 유효 입력 → canonical 형태", arguments: [
    ("1 1 1 1", "1.1.1.1"),                     // 한글 12.2 whole-bar
    ("146 4 4 240", "146.4.4.240"),             // 영문 12.2 비-bar-aligned
    ("146 4 4 240.", "146.4.4.240"),            // ★ 영문 UI 끝 마침표 (이번 fix 핵심)
    ("146 4 4 240,", "146.4.4.240"),            // 끝 콤마 방어
    ("  146 4 4 240  ", "146.4.4.240"),         // 양쪽 공백
    ("146  4  4  240", "146.4.4.240"),          // 다중 공백
    ("146\t4\t4\t240", "146.4.4.240"),          // 탭
    ("17 2 3 4", "17.2.3.4"),                   // 정확 4 컴포넌트
])
func parseMarkerListPosition_valid(input: String, expected: String) {
    #expect(AXLogicProElements.parseMarkerListPosition(input) == expected)
}
```

### 3.2 Test 2: 무효 입력 (17 cases)
```swift
@Test("parseMarkerListPosition: 무효 입력 → nil", arguments: [
    "", "   ", ".",                              // 빈 / 의미 없음
    "abc", "1 abc", "1 2 3 x",                   // 비숫자 혼합
    "1", "17 2", "1 2 3",                        // ★ NG11 strict — 1-3 components 거부
    "1 2 3 4 5", "1 2 3 4 5 6",                  // 5+ components
    "0 0 0 0", "0 1 1 1", "1 0 1 1",             // NG8 1-based 위반
    "١٤٦ ٤ ٤ ٢٤٠",                              // NG9 ASCII narrow (Arabic-Indic)
    "1.1 1.1", "146.4 4 240",                    // NG7 mixed separator
])
func parseMarkerListPosition_invalid(input: String) {
    #expect(AXLogicProElements.parseMarkerListPosition(input) == nil)
}
```

### 3.3 통합 회귀 (T3로 분리 — 호출자 fallback)
T3에서 별도 작성.

## 4. Implementation Steps

1. **Red**: 위 2개 `@Test`를 `Tests/LogicProMCPTests/AXMarkers12MarkerListTests.swift`에 추가. 기존 v3.1.10 valid/invalid 테스트는 일단 보존.
2. **Run**: `swift test --filter parseMarkerListPosition_valid` → trailing-dot 등 신규 케이스 FAIL 확인 (Red).
3. **Green** (T1 구현 후): 모든 25 cases PASS.
4. **Refactor**: 기존 v3.1.10 valid `_validInputs` / `_invalidInputs` 삭제. parameterized 2개로 통합.
5. **Final run**: `swift test --no-parallel` 1062 → 1075+ PASS.

## 5. Edge Cases
PRD §5 모두 커버.

## 6. Review Checklist
- [x] swift-testing-pro 패턴 (parameterized)
- [x] 한글 주석
- [x] 컴팩트 (50 lines)
- [x] 모든 PRD edge case 매핑
- [x] Behavior change 명시 (`"17 2"` invalid 이동)
