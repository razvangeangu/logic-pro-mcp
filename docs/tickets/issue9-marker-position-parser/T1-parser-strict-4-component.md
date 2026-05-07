# T1: parseMarkerListPosition strict 4-component fix (한글 주석)

**PRD Ref**: PRD-issue9 > US-1, US-2 (parser scope)
**Priority**: P0
**Size**: S (< 1h)
**Status**: Todo
**Depends On**: None

---

## 1. Objective
`AXLogicProElements.parseMarkerListPosition`을 PRD §4.4 sketch 그대로 구현. 18-20 라인 (doc + body), 한글 주석, Apple stdlib API only, 단일 책임.

## 2. Acceptance Criteria
- [ ] AC-1: 함수 본문 ≤ 13 lines (signature `{` ~ `}`).
- [ ] AC-2: API signature 변경 0: `static func parseMarkerListPosition(_ raw: String) -> String?`.
- [ ] AC-3: 모든 신규/수정 코드 한글 주석 (식별자는 영문 그대로).
- [ ] AC-4: NG7 (mixed separator) / NG8 (1-based) / NG9 (ASCII narrow) / NG11 (strict 4) 모두 만족.
- [ ] AC-5: Foundation API only — regex / NSRegularExpression / 외부 라이브러리 0건.
- [ ] AC-6: SOLID/SRP — pure function, side-effect 0, 다른 모듈 호출 0.
- [ ] AC-7: `swift build -c release` 0 warnings.

## 3. TDD Spec (Red Phase)

T1 단독은 implementation. Red 테스트는 T2에서 추가 — T2 빨강 → T1 초록 → T2 패라미터화 검증.

진행 순서:
1. T2 먼저: 신규 25 테스트 케이스 작성 → 모두 fail 확인 (Red).
2. T1 구현 → T2 모두 pass 확인 (Green).
3. T1 + T2 함께 commit.

## 4. Implementation

### 4.1 Files to Modify
| File | Change |
|------|--------|
| `Sources/LogicProMCP/Accessibility/AXLogicProElements.swift` | `parseMarkerListPosition` 본문 + doc 교체 |

### 4.2 Implementation (PRD §4.4)

기존 함수 (line 868-880, 14 lines)를 다음으로 교체:

```swift
/// Logic Marker List 셀의 위치 문자열을 표준 "bar.beat.div.tick" 형태로 변환한다.
///
/// 관찰된 입력 변형:
/// - 한글 12.2: "1 1 1 1" (공백 구분, whole-bar)
/// - 영문 12.2: "146 4 4 240." (공백 구분 + UI 끝 마침표)
///
/// 정확히 4 컴포넌트, 각 ASCII 정수 1 이상이어야 한다. Logic UI는 항상 4
/// 컴포넌트를 노출하므로 1-3 컴포넌트는 비-position 셀(예: tempo)일 가능성
/// 으로 nil 반환한다. 호출자는 `\(index+1).1.1.1` fallback을 사용한다.
static func parseMarkerListPosition(_ raw: String) -> String? {
    // 끝의 마침표/콤마는 Logic UI rendering artifact — 반복 strip.
    var trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    while let last = trimmed.last, last == "." || last == "," {
        trimmed.removeLast()
    }
    // 공백/탭만 separator (Logic은 공백만 사용; 점은 끝에서만 의미).
    let parts = trimmed.split(whereSeparator: \.isWhitespace).map(String.init)
    // 정확히 4 컴포넌트 + ASCII 정수 + 1-based.
    guard parts.count == 4,
          parts.allSatisfy({ Int($0).map { $0 >= 1 } == true }) else {
        return nil
    }
    return parts.joined(separator: ".")
}
```

### 4.3 Refactor (Green 후)
- `Int($0).map { $0 >= 1 } == true` 가독성 비교: `Int($0).flatMap { $0 >= 1 ? $0 : nil } != nil` 또는 `(Int($0) ?? 0) >= 1`. 후자가 가장 간결 (15 chars vs 27 chars). 단, "0이 입력이면 0 >= 1은 false" — 동일 의미. **선택**: `(Int($0) ?? 0) >= 1` (가독성 + 컴팩트).

최종 v0.4 sketch:
```swift
guard parts.count == 4,
      parts.allSatisfy({ (Int($0) ?? 0) >= 1 }) else {
    return nil
}
```

### 4.4 Verification
- `swift build -c release` 0 warnings
- `wc -l` 본문 ≤ 13 lines
- 모든 주석 한글 (식별자 제외)

## 5. Edge Cases
T2의 25 cases 매트릭스로 모두 커버.

## 6. Review Checklist (11 원칙 매핑)
- [x] Apple-level — Foundation API only, 13 lines body
- [x] 데드코드 0
- [x] 한글 주석
- [x] SOLID — single responsibility (string→canonical)
- [x] 가독성 — 단계별 의도 명료
- [x] 컴팩트 — 5 line body
- [x] 표준 — Swift API Design Guidelines 준수
