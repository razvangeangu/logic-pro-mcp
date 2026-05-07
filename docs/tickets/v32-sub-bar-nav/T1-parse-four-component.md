# T1 — `parseFourComponentPosition` Helper

**Status**: Todo (T0 PASS 후 진행)
**Size**: S
**의존성**: T0
**PRD**: AC-1.1, AC-2.1~2.4, AC-4.4, AC-4.5

## 목표

`gotoPositionViaBarSlider` 가 `params["position"]` 의 4-component string 을 정확히 추출하는 helper 함수 분리. v3.1.11 parser (`parseMarkerListPosition`) 와는 다른 책임 — caller validation/extraction.

## 배경

v3.1.11 코드:

```swift
// AccessibilityChannel.swift:2206-2208
let parts = pos.split(separator: ".")
if let first = parts.first, let b = Int(first) {
    targetBar = b
}
```

첫 컴포넌트만 추출. v3.2 — 4 컴포넌트 모두 추출.

TransportDispatcher 가 이미 `isValidPositionString` 으로 4-component 형식 검증 → AccessibilityChannel 에 도달한 시점에 `pos` 는 valid 한 4-component string 임. 그러나 AX channel 도 self-contained validation 유지 (defense in depth).

## TDD Red Phase

`Tests/LogicProMCPTests/AXGotoPositionTests.swift` 에 추가 (or 신규 파일):

```swift
@Test("parseFourComponentPosition: 유효 → (bar, beat, div, tick)", arguments: [
    ("146.4.4.240", (146, 4, 4, 240)),
    ("1.1.1.1", (1, 1, 1, 1)),
    ("9999.16.16.999", (9999, 16, 16, 999)),
])
func parseFourComponentPosition_valid(input: String, expected: (Int, Int, Int, Int)) {
    let parsed = AccessibilityChannel.parseFourComponentPosition(input)
    #expect(parsed?.bar == expected.0)
    #expect(parsed?.beat == expected.1)
    #expect(parsed?.div == expected.2)
    #expect(parsed?.tick == expected.3)
}

@Test("parseFourComponentPosition: 무효 → nil", arguments: [
    "", "146", "146.4", "146.4.4", "146.4.4.240.1",
    "0.1.1.1", "10000.1.1.1", "146.17.4.240", "146.4.17.240", "146.4.4.1000",
    "abc.4.4.240", "146.+4.4.240", "146.-4.4.240", "146.4.4.240.",
    "00:01:30:00",
])
func parseFourComponentPosition_invalid(input: String) {
    #expect(AccessibilityChannel.parseFourComponentPosition(input) == nil)
}
```

**Red 확인**: 함수 정의 전 — `parseFourComponentPosition` 존재 안 함 → 컴파일 에러 → Red.

## Green Phase 구현

`Sources/LogicProMCP/Channels/AccessibilityChannel.swift` 에 추가:

```swift
/// `transport.goto_position` 의 4-component position string을 분해한다.
///
/// 입력은 TransportDispatcher.isValidPositionString 검증 통과 후 전달되지만,
/// AX channel도 self-contained validation 유지 — defense-in-depth.
/// Bound: bar 1..9999, beat 1..16, div 1..16, tick 1..999.
/// `+`/`-` prefix, 비-ASCII digit, timecode (`:` 포함) 거부.
struct FourComponentPosition: Equatable {
    let bar: Int
    let beat: Int
    let div: Int
    let tick: Int
}

static func parseFourComponentPosition(_ raw: String) -> FourComponentPosition? {
    // timecode 명시적 거부 (caller가 잘못된 channel 라우팅한 경우 방어).
    guard !raw.contains(":") else { return nil }
    let parts = raw.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
    guard parts.count == 4 else { return nil }
    // ASCII 0-9 char-set check (v3.1.11 NG9와 동일 정책).
    let asciiDigit = { (s: String) -> Bool in
        !s.isEmpty && s.allSatisfy { $0.isASCII && $0.isNumber }
    }
    guard parts.allSatisfy(asciiDigit),
          let bar = Int(parts[0]), (1...9999).contains(bar),
          let beat = Int(parts[1]), (1...16).contains(beat),
          let div = Int(parts[2]), (1...16).contains(div),
          let tick = Int(parts[3]), (1...999).contains(tick) else {
        return nil
    }
    return FourComponentPosition(bar: bar, beat: beat, div: div, tick: tick)
}
```

본문 ≤ 25 lines (AC-4.5).

## Refactor Phase

- 한글 주석 점검 (영어 주석 추가 금지 — AC-4.1)
- TODO/FIXME grep 0건 (AC-4.2)
- `static`/`internal` 가시성 — 테스트가 internal 접근 필요. Swift Testing은 `@testable import` 사용 → `static func` 으로 충분
- 명명: Swift API Design Guidelines (`parseFourComponentPosition` — verb phrase, side-effect-free 명사 query). Struct `FourComponentPosition` PascalCase

## Acceptance Criteria

- **AC-T1.1**: `AccessibilityChannel.parseFourComponentPosition` 함수 추가, body ≤ 25 lines
- **AC-T1.2**: parameterized test 3 valid + 15 invalid cases PASS
- **AC-T1.3**: 한글 주석만 (영어 주석 0건 — git diff grep 검증)
- **AC-T1.4**: 신규 TODO/FIXME/XXX 0건
- **AC-T1.5**: 기존 1064 tests 회귀 0건 (PASS 유지)
- **AC-T1.6**: SOLID/SRP — parser 함수 (`parseMarkerListPosition`) 와 책임 분리 (parser는 AX surface 변환, 본 함수는 caller input extraction)

## Out of Scope

- 본 helper는 추출만 — actual navigation 은 T2
- TransportDispatcher 측 검증 변경 0건 (기존 isValidPositionString 유지)
- 1-component 또는 SMPTE 처리는 호출 site (T2) 에서 분기
