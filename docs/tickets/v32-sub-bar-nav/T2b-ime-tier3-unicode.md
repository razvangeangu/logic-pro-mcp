# T2b — IME Mitigation Tier 3: `CGEventKeyboardSetUnicodeString` (Conditional)

> Historical record (2026-06-05 docs refresh): latest production-readiness and live E2E evidence is in `README.md`, `CHANGELOG.md`, and `docs/live-verify-v3.4.5-rc5.md`; this file remains preserved implementation context.

**Status**: Conditional — only if T0 S1 (English build + English IME) FAIL
**Size**: M
**Depends on**: T0 result + T2
**PRD**: §3.5 Tier 3
**Boomer Phase E P1-2 fix**: Deepest fallback when T0 S1 FAIL. Uses the actual Apple Unicode injection API.

## Activation Condition

T0 spike result:
- S1 PASS → skip (use Tier 0 or Tier 1)
- S1 FAIL → this ticket **activates** (keystroke fails in all environments)
- All scenarios FAIL → retire v3.2 navigation scope (ship provenance only — drastic)

## Implementation

New helper in `Sources/LogicProMCP/Channels/CGEventChannel.swift`:

```swift
/// IME-agnostic Unicode input via `CGEventKeyboardSetUnicodeString`.
/// Different from existing `keyStroke(for:)` (keycode-based) —
/// keycode is layout-dependent, Unicode injection is OS-layer string injection.
///
/// Apple docs: <https://developer.apple.com/documentation/coregraphics/1454618-cgeventkeyboardsetunicodestring>
static func postUnicodeString(_ s: String, pid: pid_t) -> Bool {
    guard let source = CGEventSource(stateID: .hidSystemState) else { return false }
    let utf16 = Array(s.utf16)
    guard let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true) else {
        return false
    }
    utf16.withUnsafeBufferPointer { buf in
        guard let base = buf.baseAddress else { return }
        CGEventKeyboardSetUnicodeString(event, buf.count, base)
    }
    event.postToPid(pid)
    // Also send keyUp event — paired event required for Cocoa input system compatibility.
    if let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) {
        utf16.withUnsafeBufferPointer { buf in
            if let base = buf.baseAddress {
                CGEventKeyboardSetUnicodeString(up, buf.count, base)
            }
        }
        up.postToPid(pid)
    }
    return true
}
```

Call from `gotoPositionViaDialog`:

```swift
let posStr = "\(p.bar).\(p.beat).\(p.div).\(p.tick)"
guard let pid = LogicProRuntimeInfo.logicProPID() else { return .error(...) }
let ok = CGEventChannel.postUnicodeString(posStr, pid: pid)
```

## TDD Red Phase

```swift
@Test
func postUnicodeString_returnsTrue_forValidInput() {
    // CGEvent creation succeeds even without Logic Pro running
    // (transmission is silently ignored when PID is absent)
    let ok = CGEventChannel.postUnicodeString("146.4.4.240", pid: 0)
    #expect(ok)
}

@Test
func postUnicodeString_emptyString_returnsTrue() {
    let ok = CGEventChannel.postUnicodeString("", pid: 0)
    #expect(ok)  // CGEvent creation succeeds — empty Unicode buffer is OK
}
```

(Live verification is permanently recorded in T9 runbook Tier 2.5 — must PASS for both English build / Korean IME ON)

## Acceptance Criteria

- **AC-T2b.1**: `CGEventChannel.postUnicodeString(s, pid)` new helper added
- **AC-T2b.2**: keyDown + keyUp events sent as a pair (Cocoa compatible)
- **AC-T2b.3**: Body ≤ 35 lines
- **AC-T2b.4**: Korean comments (Apple API link + WHY: difference from keycode)
- **AC-T2b.5**: Live scenarios S1+S2+S3 all PASS — T9 runbook
- **AC-T2b.6**: Existing `keyStroke(for:)` (keycode-based) behavior: 0 regressions — separate helper

## Risk

- `CGEventKeyboardSetUnicodeString` may not work in Logic Pro's specific input field. T0 is the most accurate pre-validation.
- macOS 14/15 compatibility — Apple API changes could cause regressions. v3.3 mitigation: live self-test.
