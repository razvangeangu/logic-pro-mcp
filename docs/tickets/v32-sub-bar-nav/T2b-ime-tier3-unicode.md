# T2b — IME Mitigation Tier 3: `CGEventKeyboardSetUnicodeString` (Conditional)

**Status**: Conditional — only if T0 S1 (영문빌드+영문IME) FAIL
**Size**: M
**의존성**: T0 결과 + T2
**PRD**: §3.5 Tier 3
**Boomer Phase E P1-2 fix**: T0 S1 FAIL 시 가장 깊은 fallback. 실제 Apple Unicode injection API.

## 발동 조건

T0 spike 결과:
- S1 PASS → skip (Tier 0 또는 Tier 1 사용)
- S1 FAIL → 본 티켓 **발동** (모든 환경에서 keystroke 실패)
- 모든 시나리오 FAIL → v3.2 navigation scope 폐기 (provenance만 ship — drastic)

## 구현

`Sources/LogicProMCP/Channels/CGEventChannel.swift` 신규 helper:

```swift
/// `CGEventKeyboardSetUnicodeString` 사용한 IME-agnostic Unicode 입력.
/// 기존 `keyStroke(for:)` (keycode 기반)와 다름 — keycode는 layout-dependent,
/// Unicode injection은 OS-layer string injection.
///
/// Apple 문서: <https://developer.apple.com/documentation/coregraphics/1454618-cgeventkeyboardsetunicodestring>
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
    // keyUp 이벤트도 추가 — paired event 필수 (Cocoa input system 호환).
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

`gotoPositionViaDialog` 에서 호출:

```swift
let posStr = "\(p.bar).\(p.beat).\(p.div).\(p.tick)"
guard let pid = LogicProRuntimeInfo.logicProPID() else { return .error(...) }
let ok = CGEventChannel.postUnicodeString(posStr, pid: pid)
```

## TDD Red Phase

```swift
@Test
func postUnicodeString_returnsTrue_forValidInput() {
    // 실제 Logic Pro 미실행 환경에서도 CGEvent 생성 자체는 성공
    // (전송은 PID 부재 시 silently 무시)
    let ok = CGEventChannel.postUnicodeString("146.4.4.240", pid: 0)
    #expect(ok)
}

@Test
func postUnicodeString_emptyString_returnsTrue() {
    let ok = CGEventChannel.postUnicodeString("", pid: 0)
    #expect(ok)  // CGEvent 생성 성공 — Unicode buffer 비어 있어도 OK
}
```

(라이브 검증은 T9 runbook Tier 2.5에 영구 기록 — 영문 빌드 / 한글 IME ON 모두 PASS 필수)

## Acceptance Criteria

- **AC-T2b.1**: `CGEventChannel.postUnicodeString(s, pid)` 신규 helper 추가
- **AC-T2b.2**: keyDown + keyUp 이벤트 paired 전송 (Cocoa 호환)
- **AC-T2b.3**: 본문 ≤ 35 lines
- **AC-T2b.4**: 한글 주석 (Apple API 링크 + WHY: keycode와 차이)
- **AC-T2b.5**: 라이브 시나리오 S1+S2+S3 모두 PASS — T9 runbook
- **AC-T2b.6**: 기존 `keyStroke(for:)` (keycode 기반) 동작 회귀 0 — 별도 helper

## Risk

- `CGEventKeyboardSetUnicodeString` 가 Logic Pro의 specific input field에서 동작 안 할 수 있음. T0 가 가장 정확한 사전 검증.
- macOS 14/15 호환성 — Apple API 변경 시 회귀 가능. v3.3 mitigation: 라이브 self-test.
