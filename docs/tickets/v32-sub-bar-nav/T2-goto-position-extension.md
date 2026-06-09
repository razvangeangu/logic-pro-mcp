# T2 — `gotoPositionViaBarSlider` 4-Component Extension (+ AppleScript Runner Test Seam)

> Historical record (2026-06-09 docs refresh): latest production-readiness and live E2E evidence is in `README.md`, `CHANGELOG.md`, and `docs/live-verify-v3.4.5.md`; this file remains preserved implementation context.

**Status**: Todo (after T1 complete)
**Size**: M
**Depends on**: T1
**PRD**: AC-1.1, AC-1.4, AC-1.5, AC-1.6, AC-4.6
**Boomer Phase E P1-3 fix**: AppleScript dialog call test seam required — current `gotoPositionViaDialog` calls `AppleScriptChannel.executeAppleScript` directly → cannot be unit tested. This ticket adds runner injection.

## Goal

Extend `gotoPositionViaBarSlider` to use all 4 components. Dialog path uses 4-component string keystroke. Slider fallback uses bar+beat partial.

## Test Seam Introduction (Boomer P1-3)

`gotoPositionViaDialog` calls `AppleScriptChannel.executeAppleScript` directly → cannot run real AppleScript in tests. v3.2 new: runner closure injection.

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

`gotoPositionViaBarSlider` extended with the same signature:

```swift
private static func gotoPositionViaBarSlider(
    params: [String: String],
    runtime: AXLogicProElements.Runtime = .production,
    appleScriptRunner: AppleScriptRunner = AppleScriptChannel.executeAppleScript
) async -> ChannelResult { ... }
```

Existing callers (channel layer) use default args → 0 changes. Only tests inject the closure.

## TDD Red Phase

```swift
@Test
func gotoPosition_fourComponent_dialogSucceeds() async {
    // AppleScript runner stub — returns "OK" without showing real dialog
    let stubRunner: AppleScriptRunner = { _ in .success("OK") }
    let params = ["position": "146.4.4.240"]
    let result = await AccessibilityChannel.gotoPositionViaBarSlider(
        params: params, appleScriptRunner: stubRunner
    )
    if case .success(let json) = result {
        // HC State A/B is flat top-level "success":true + extras merged (HonestContract.swift:73-89)
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

**Red confirmation**: 
1. Current `gotoPositionViaBarSlider` signature has no `appleScriptRunner` parameter → compile error
2. Existing code sets only `targetBar` → returns `requested: "146.1.1.1"` → `requested:"146.4.4.240"` assertion FAIL

## Green Phase Implementation

Modify `gotoPositionViaBarSlider`:

```swift
private static func gotoPositionViaBarSlider(
    params: [String: String],
    runtime: AXLogicProElements.Runtime = .production,
    appleScriptRunner: AppleScriptRunner = AppleScriptChannel.executeAppleScript
) async -> ChannelResult {
    // Input branch: bar integer / position 4-component / other.
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

    // Dialog path — 4-component precision. Runner injection (test seam).
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

`gotoPositionViaDialog` signature change: `bar: Int` → `position: FourComponentPosition`. AppleScript keystroke `"\(p.bar).\(p.beat).\(p.div).\(p.tick)"`.

`gotoPositionViaSliderPartial` new function — sets bar slider + beat slider only. Ignores div/tick. extras `precision: "bar_beat"` included.

## Refactor Phase

- `gotoPositionViaSliderPartial` body ≤ 30 lines
- Korean comments (structure + WHY)
- TODO/FIXME 0
- Existing dialog function compatibility: AppleScript `keystroke "\(p.bar)"` → `keystroke "\(p.bar).\(p.beat).\(p.div).\(p.tick)"` single change. 1.1.1.1 input must reach same position as `keystroke "1"` (bar 1 start) — verify in T0 spike

## IME Mitigation Branch (depends on T0 results)

| T0 result | This ticket implementation |
|-----------|---------------------------|
| 3/3 PASS | Simple `keystroke "\(requested)"` |
| S3 FAIL | NSPasteboard save+restore + paste |
| S2/S3 FAIL | Force ABC input source |
| S1 FAIL | `CGEventKeyboardSetUnicodeString` (**T2b** separate sub-ticket) |

## Acceptance Criteria

- **AC-T2.1**: 4 valid scenario unit tests PASS (dialog success / slider partial / bar integer / invalid)
- **AC-T2.2**: Dialog path uses 4-component string keystroke
- **AC-T2.3**: Slider fallback sets bar+beat, does not attempt div/tick, extras `precision: "bar_beat"`
- **AC-T2.4**: 1-component / 5-component / 0 / 10000 / beat 17 etc. invalid → State C error
- **AC-T2.5**: Korean comments only, no new TODOs
- **AC-T2.6**: Existing dialog tests: 0 regressions (if `gotoPositionViaDialog` signature changes, synchronize existing callers)

## Out of Scope

- IME mitigation implementation (sub-ticket branch based on T0 results)
- MarkerState provenance (T3-T6)
- Documentation updates (T8)
