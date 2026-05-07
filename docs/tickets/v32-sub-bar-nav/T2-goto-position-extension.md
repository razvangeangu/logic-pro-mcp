# T2 — `gotoPositionViaBarSlider` 4-Component 확장 (+ AppleScript Runner Test Seam)

**Status**: Todo (T1 완료 후)
**Size**: M
**의존성**: T1
**PRD**: AC-1.1, AC-1.4, AC-1.5, AC-1.6, AC-4.6
**Boomer Phase E P1-3 fix**: AppleScript dialog 호출 test seam 필수 — 현재 `gotoPositionViaDialog`는 `AppleScriptChannel.executeAppleScript` 직접 호출 → unit test 불가. 본 티켓에서 runner injection 추가.

## 목표

`gotoPositionViaBarSlider` 가 4 컴포넌트 모두 사용하도록 확장. Dialog path는 4-component string keystroke. Slider fallback은 bar+beat partial.

## Test Seam 도입 (Boomer P1-3)

`gotoPositionViaDialog` 가 직접 `AppleScriptChannel.executeAppleScript` 호출 → 테스트에서 AppleScript 실제 실행 불가능. v3.2 신규: runner closure injection.

```swift
typealias AppleScriptRunner = (String) async -> ChannelResult

private static func gotoPositionViaDialog(
    position: FourComponentPosition,
    appleScriptRunner: AppleScriptRunner = AppleScriptChannel.executeAppleScript
) async -> ChannelResult {
    ...
    let result = await appleScriptRunner(script)
    ...
}
```

`gotoPositionViaBarSlider` 도 같은 시그니처 확장:

```swift
private static func gotoPositionViaBarSlider(
    params: [String: String],
    runtime: AXLogicProElements.Runtime = .production,
    appleScriptRunner: AppleScriptRunner = AppleScriptChannel.executeAppleScript
) async -> ChannelResult { ... }
```

기존 caller (channel layer)는 default arg 사용 → 변경 0. 테스트만 closure 주입.

## TDD Red Phase

```swift
@Test
func gotoPosition_fourComponent_dialogSucceeds() async {
    // AppleScript runner stub — 실제 dialog 띄우지 않고 "OK" 반환
    let stubRunner: AppleScriptRunner = { _ in .success("OK") }
    let params = ["position": "146.4.4.240"]
    let result = await AccessibilityChannel.gotoPositionViaBarSlider(
        params: params, appleScriptRunner: stubRunner
    )
    if case .success(let json) = result {
        // HC State A/B는 top-level "success":true + extras 머지 (HonestContract.swift:73-89)
        #expect(json.contains("\"requested\":\"146.4.4.240\""))
        #expect(json.contains("\"via\":\"dialog\""))
    } else {
        Issue.record("dialog path should succeed")
    }
}

@Test
func gotoPosition_dialogDisabled_fallsThroughToSliderPartial() async {
    // dialog returns MENU_DISABLED → slider fallback
    let stubRunner: AppleScriptRunner = { _ in .success("MENU_DISABLED") }
    let runtime = synthRuntimeWithBarBeatSliders(barValue: 146, beatValue: 1)
    let params = ["position": "146.4.4.240"]
    let result = await AccessibilityChannel.gotoPositionViaBarSlider(
        params: params, runtime: runtime, appleScriptRunner: stubRunner
    )
    if case .success(let json) = result {
        // HC State B top-level: "success":true, "verified":false, "reason":"readback_unavailable"
        #expect(json.contains("\"reason\":\"readback_unavailable\""))
        #expect(json.contains("\"precision\":\"bar_beat\""))
    } else {
        Issue.record("slider partial fallback should succeed")
    }
}

@Test
func gotoPosition_barIntegerInput_dialogSucceeds() async {
    let stubRunner: AppleScriptRunner = { _ in .success("OK") }
    let params = ["bar": "146"]
    let result = await AccessibilityChannel.gotoPositionViaBarSlider(
        params: params, appleScriptRunner: stubRunner
    )
    if case .success(let json) = result {
        #expect(json.contains("\"requested\":\"146.1.1.1\""))
    } else {
        Issue.record("bar integer input should succeed")
    }
}

@Test
func gotoPosition_invalidPosition_returnsStateC() async {
    let stubRunner: AppleScriptRunner = { _ in .success("OK") }
    let params = ["position": "146.4.4.240.1"]  // 5-component
    let result = await AccessibilityChannel.gotoPositionViaBarSlider(
        params: params, appleScriptRunner: stubRunner
    )
    if case .error = result {
        // expected — parseFourComponentPosition returns nil
    } else {
        Issue.record("5-component should return State C error")
    }
}
```

**Red 확인**: 
1. 현재 `gotoPositionViaBarSlider` 시그니처에 `appleScriptRunner` 파라미터 없음 → 컴파일 에러
2. 기존 코드는 `targetBar` 만 set → `requested: "146.1.1.1"` 반환 → `requested:"146.4.4.240"` assertion FAIL

## Green Phase 구현

`gotoPositionViaBarSlider` 수정:

```swift
private static func gotoPositionViaBarSlider(
    params: [String: String],
    runtime: AXLogicProElements.Runtime = .production,
    appleScriptRunner: AppleScriptRunner = AppleScriptChannel.executeAppleScript
) async -> ChannelResult {
    // 입력 분기: bar 정수 / position 4-component / 기타.
    let position: FourComponentPosition?
    if let barStr = params["bar"], let b = Int(barStr), (1...9999).contains(b) {
        position = FourComponentPosition(bar: b, beat: 1, div: 1, tick: 1)
    } else if let pos = params["position"] {
        position = parseFourComponentPosition(pos)
    } else {
        position = nil
    }

    guard let p = position else {
        return .error(HonestContract.encodeStateC(
            error: .invalidParams,
            hint: "goto_position requires 'bar' (1..9999) or 'position' (B.B.D.T)"
        ))
    }

    let requested = "\(p.bar).\(p.beat).\(p.div).\(p.tick)"
    let baseExtras: [String: Any] = ["requested": requested]

    // Dialog path — 4-component 정밀. runner 주입 (test seam).
    let dialogResult = await gotoPositionViaDialog(
        position: p, appleScriptRunner: appleScriptRunner
    )
    if case .success = dialogResult { return dialogResult }

    // Slider fallback — bar+beat partial.
    return await gotoPositionViaSliderPartial(
        position: p, baseExtras: baseExtras, runtime: runtime
    )
}
```

`gotoPositionViaDialog` 시그니처 변경: `bar: Int` → `position: FourComponentPosition`. AppleScript keystroke `"\(p.bar).\(p.beat).\(p.div).\(p.tick)"`.

`gotoPositionViaSliderPartial` 신규 — bar slider + beat slider 만 set. div/tick 무시. extras `precision: "bar_beat"` 명시.

## Refactor Phase

- `gotoPositionViaSliderPartial` 본문 ≤ 30 lines
- 한글 주석 (구조 + WHY)
- TODO/FIXME 0
- 기존 dialog 함수 호환성: AppleScript `keystroke "\(p.bar)"` → `keystroke "\(p.bar).\(p.beat).\(p.div).\(p.tick)"` 단일 변경. 1.1.1.1 입력 시 기존 `keystroke "1"` 와 동일 위치로 도달 (bar 1 시작) 보장 필요 — T0 spike에서 검증

## IME mitigation 분기 (T0 결과 의존)

| T0 결과 | 본 티켓 구현 |
|---------|--------------|
| 3/3 PASS | 단순 `keystroke "\(requested)"` |
| S3 FAIL | NSPasteboard save+restore + paste |
| S2/S3 FAIL | input source ABC 강제 |
| S1 FAIL | `CGEventKeyboardSetUnicodeString` (**T2b** 별도 sub-ticket) |

## Acceptance Criteria

- **AC-T2.1**: 4 valid 시나리오 unit test PASS (dialog success / slider partial / bar integer / invalid)
- **AC-T2.2**: dialog path 가 4-component string keystroke 사용
- **AC-T2.3**: slider fallback 이 bar+beat 까지 set, div/tick 미시도, extras `precision: "bar_beat"`
- **AC-T2.4**: 1-component / 5-component / 0 / 10000 / beat 17 등 invalid → State C error
- **AC-T2.5**: 한글 주석만, 신규 TODO 0건
- **AC-T2.6**: 기존 dialog tests 회귀 0건 (`gotoPositionViaDialog` 시그니처 변경 시 기존 caller 동기 변경)

## Out of Scope

- IME mitigation 구현 (T0 결과에 따라 sub-ticket 분기)
- MarkerState provenance (T3-T6)
- 문서 업데이트 (T8)
