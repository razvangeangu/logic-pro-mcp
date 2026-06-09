# T2a — IME Mitigation Tier 1: Pasteboard Paste (Conditional)

> Historical record (2026-06-09 docs refresh): latest production-readiness and live E2E evidence is in `README.md`, `CHANGELOG.md`, and `docs/live-verify-v3.4.6.md`; this file remains preserved implementation context.

**Status**: Conditional — only if T0 S3 (Korean IME ON) FAIL
**Size**: S
**Depends on**: T0 result + T2 (leverages test seam)
**PRD**: §3.5 Tier 1
**Boomer Phase E P1-2 fix**: IME mitigation implementation explicitly specified per T0 branch.

## Activation Condition

T0 spike result:
- S1 PASS, S2 PASS, S3 FAIL → this ticket **activates**
- 3/3 PASS → **skip** (Tier 0 keystroke used directly)
- S1 FAIL → branch to T2b (Unicode injection)

## Implementation

Inside `gotoPositionViaDialog`, use NSPasteboard paste instead of keystroke:

```swift
private static func keystrokePositionViaPasteboard(_ position: String) async -> Bool {
    let pb = NSPasteboard.general
    // Preserve user clipboard (boomer mitigation P2-2 risk).
    let savedItems = pb.pasteboardItems?.compactMap { item -> NSPasteboardItem? in
        let copy = NSPasteboardItem()
        for type in item.types {
            if let data = item.data(forType: type) { copy.setData(data, forType: type) }
        }
        return copy
    } ?? []

    pb.clearContents()
    pb.setString(position, forType: .string)

    // Cmd+A (select all) → Cmd+V (paste) → Return
    let script = """
    tell application "System Events"
        tell process "Logic Pro"
            keystroke "a" using command down
            delay 0.05
            keystroke "v" using command down
            delay 0.1
            keystroke return
        end tell
    end tell
    """
    let result = await AppleScriptChannel.executeAppleScript(script)
    let ok: Bool
    if case .success = result { ok = true } else { ok = false }

    // Restore clipboard after 0.1s delay.
    try? await Task.sleep(nanoseconds: 100_000_000)
    pb.clearContents()
    if !savedItems.isEmpty {
        pb.writeObjects(savedItems)
    }
    return ok
}
```

Keystroke branch selection in `gotoPositionViaDialog`:

```swift
// Select keystroke vs pasteboard based on T0 results. When Tier 1 is active:
let posStr = "\(p.bar).\(p.beat).\(p.div).\(p.tick)"
let ok = await keystrokePositionViaPasteboard(posStr)
```

## TDD Red Phase

```swift
@Test
func keystrokePositionViaPasteboard_savesAndRestoresClipboard() async {
    let pb = NSPasteboard.general
    pb.clearContents()
    pb.setString("user-content", forType: .string)
    
    _ = await AccessibilityChannel.keystrokePositionViaPasteboard("146.4.4.240")
    
    // Wait 0.2s+ before verifying — allow sufficient restore time
    try? await Task.sleep(nanoseconds: 300_000_000)
    let restored = pb.string(forType: .string)
    #expect(restored == "user-content")
}
```

(Live device testing is permanently recorded in T9 runbook Tier 2.5)

## Acceptance Criteria

- **AC-T2a.1**: pasteboard save/restore behavior verified (user clipboard preserved)
- **AC-T2a.2**: AppleScript Cmd+A → Cmd+V → Return sequence correct
- **AC-T2a.3**: Live scenario with Korean IME ON reaches accurate sub-bar nav (recorded in T9 runbook)
- **AC-T2a.4**: Body ≤ 30 lines (compact)
- **AC-T2a.5**: Korean comments, no new TODOs
- **AC-T2a.6**: Integrated with T2 dialog runner: 0 regressions in existing unit tests

## Side Effects

- User clipboard temporarily modified for ~100ms (document in CHANGELOG)
- Race condition if user simultaneously presses Cmd+V — potential issue. Additional mitigation if needed → v3.3
