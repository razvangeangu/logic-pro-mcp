# T0 — Live Spike: 4-Component Dialog + 3 IME Scenarios (Release Gate)

> Historical record (2026-06-09 docs refresh): latest production-readiness and live E2E evidence is in `README.md`, `CHANGELOG.md`, and `docs/live-verify-v3.4.6.md`; this file remains preserved implementation context.

**Status**: Blocked — requires Isaac + Logic Pro 12.2 on a real device
**Size**: S (manual)
**Owner**: Isaac
**Type**: Release gate — mandatory validation before implementation begins
**PRD**: §3.4 + §3.5

## Goal

Validate by **direct measurement** the assumption made in PRD v0.4 AC-1.1: "Logic 12.2 dialog natively accepts 4-component `bar.beat.div.tick` text input." Also confirm whether AppleScript `keystroke` drops `.` when the Korean IME is active.

## Prerequisites

1. Logic Pro 12.2 running
2. New project created (BPM 120, 4/4)
3. At least 1 region (drum loop or empty audio track region) — dialog is disabled in an empty project
4. AppleScript Editor or terminal `osascript` available

## Scenarios

### S1 — English build (English IME)

System Settings → Language & Region → Apps → Logic Pro → English. Restart Logic.

```applescript
tell application "Logic Pro" to activate
delay 0.2
tell application "System Events"
    tell process "Logic Pro"
        click menu item "Position…" of menu 1 of menu item "Go To" of menu 1 of menu bar item "Navigate" of menu bar 1
        delay 0.3
        keystroke "a" using command down
        delay 0.1
        keystroke "146.4.4.240"
        delay 0.1
        keystroke return
        delay 0.5
    end tell
end tell
```

**Expected**: Logic's top-left Position display changes to `146.4.4.240` (or equivalent display).

### S2 — Korean build (Korean IME OFF — English input mode)

System Settings → Language & Region → Apps → Logic Pro → Korean. Restart Logic. Input method set to English mode (Caps Lock OFF / toggle key set to English).

```applescript
tell application "Logic Pro" to activate
delay 0.2
tell application "System Events"
    tell process "Logic Pro"
        click menu item "위치…" of menu 1 of menu item "이동" of menu 1 of menu bar item "탐색" of menu bar 1
        delay 0.3
        keystroke "a" using command down
        delay 0.1
        keystroke "146.4.4.240"
        delay 0.1
        keystroke return
        delay 0.5
    end tell
end tell
```

**Expected**: Same.

### S3 — Korean build (Korean IME ON — Hangul mode)

Same environment as S2 but **toggle input to Korean (Hangul) mode**. System menu bar input indicator shows "한". Run the same AppleScript.

**Expected (hypothesis)**: `keystroke "146.4.4.240"` may drop `.` in Hangul mode or convert it to another character → playhead moves to incorrect position or dialog rejects the input.

**Observations required**:
- Position display result (`146.4.4.240` vs `1464240` vs `146` vs error)
- Whether the dialog accepted the keystroke (closed or rejected)
- Status bar message at bottom-left

## Result Recording Form

```
S1 English build / English IME:        [PASS / FAIL]
   - Position display result: __________
   - Notes: __________

S2 Korean build / English IME:        [PASS / FAIL]
   - Position display result: __________
   - Notes: __________

S3 Korean build / Korean IME ON:     [PASS / FAIL]
   - Position display result: __________
   - Notes: __________
```

## Branch Criteria

| Result | Next action |
|--------|-------------|
| 3/3 PASS | Implementation Tier 0 — simple `keystroke "B.B.D.T"`. Proceed to T1-T10 |
| S1+S2 PASS, S3 FAIL | Implementation Tier 1 — pasteboard paste (NSPasteboard.general save+restore). Proceed to T1-T10 |
| S1 PASS, S2/S3 FAIL | Implementation Tier 2 — force ABC input source + restore. PRD v0.5 (risk mitigation reinforced) |
| S1 FAIL | Implementation Tier 3 — `CGEventKeyboardSetUnicodeString` Unicode injection. PRD v0.5 (Apple API + channel split) |
| All FAIL | NG10 fix not feasible. Narrow v3.2 scope — ship provenance only, defer navigation to v3.3 |

## Supplementary Validation (recommended, not mandatory)

- Check console.app logs to observe AppleScript `keystroke` behavior with IME active
- Test keystroke bypass via `do shell script "osascript -e 'do shell script ...'"` 
- Confirm exact format of Logic's top-left Position display (`bar.beat.div.tick` vs `bar . beat . div . tick`)

## Acceptance Criteria

- **AC-T0.1**: Record results of all 3 scenarios permanently in `docs/live-verify-v3.2.0.md` Tier 2
- **AC-T0.2**: Reflect branching decision in PRD v0.4 → v0.5 (or maintain v0.4 + add results)
- **AC-T0.3**: T1-T10 must not proceed without T0 results (release gate)

## Why this is a release gate

PRD v0.1 assumed "AppleScript keystroke 4-component native input" without validation. Boomer P0 (round 1) identified this exact gap. Starting implementation without direct measurement risks creating a new NG where the playhead silently moves to the wrong position in IME environments (same pattern as the v3.1.5/6/7 false-positive cycle).
