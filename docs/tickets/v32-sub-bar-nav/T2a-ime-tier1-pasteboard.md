# T2a — IME Mitigation Tier 1: Pasteboard Paste (Conditional)

**Status**: Conditional — only if T0 S3 (한글 IME ON) FAIL
**Size**: S
**의존성**: T0 결과 + T2 (test seam 활용)
**PRD**: §3.5 Tier 1
**Boomer Phase E P1-2 fix**: T0 분기에 따라 mitigation 구현 명시.

## 발동 조건

T0 spike 결과:
- S1 PASS, S2 PASS, S3 FAIL → 본 티켓 **발동**
- 3/3 PASS → **skip** (Tier 0 keystroke 직접 사용)
- S1 FAIL → T2b로 분기 (Unicode injection)

## 구현

`gotoPositionViaDialog` 안에서 keystroke 대신 NSPasteboard paste:

```swift
private static func keystrokePositionViaPasteboard(_ position: String) async -> Bool {
    let pb = NSPasteboard.general
    // 사용자 클립보드 보존 (boomer mitigation P2-2 risk).
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

    // 0.1s delay 후 클립보드 복원.
    try? await Task.sleep(nanoseconds: 100_000_000)
    pb.clearContents()
    if !savedItems.isEmpty {
        pb.writeObjects(savedItems)
    }
    return ok
}
```

`gotoPositionViaDialog` 의 keystroke 분기:

```swift
// T0 결과에 따라 keystroke vs pasteboard 선택. Tier 1 활성 시:
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
    
    // 0.2s 이상 대기 후 검증 — 복원 시간 충분히 확보
    try? await Task.sleep(nanoseconds: 300_000_000)
    let restored = pb.string(forType: .string)
    #expect(restored == "user-content")
}
```

(라이브 실기기 테스트는 T9 runbook Tier 2.5에 영구 기록)

## Acceptance Criteria

- **AC-T2a.1**: pasteboard save/restore 동작 검증 (사용자 클립보드 보존)
- **AC-T2a.2**: AppleScript Cmd+A → Cmd+V → Return 시퀀스 정확
- **AC-T2a.3**: 한글 IME ON 라이브 시나리오에서 정확한 sub-bar nav 도달 (T9 runbook 기록)
- **AC-T2a.4**: 본문 ≤ 30 lines (compact)
- **AC-T2a.5**: 한글 주석, 신규 TODO 0
- **AC-T2a.6**: T2 dialog runner와 통합 시 기존 unit test 회귀 0

## Side Effects

- 사용자 클립보드 ~100ms 잠시 변경 (CHANGELOG 명시)
- 사용자가 Cmd+V 동시 누름 시 race — 잠재 문제. 추가 mitigation 필요 시 v3.3
