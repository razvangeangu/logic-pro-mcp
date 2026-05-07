# T0 — Live Spike: 4-Component Dialog + IME 시나리오 3가지 (Release Gate)

**Status**: Blocked — Isaac + Logic Pro 12.2 실기기 필요
**Size**: S (수동)
**Owner**: Isaac
**Type**: Release gate — implementation 시작 전 필수 검증
**PRD**: §3.4 + §3.5

## 목표

PRD v0.4 AC-1.1이 가정한 "Logic 12.2 dialog가 4-component `bar.beat.div.tick` 텍스트 입력을 native하게 받는다"를 **실측**으로 검증. 동시에 한글 IME 활성 시 AppleScript `keystroke` 의 `.` 누락 여부 확인.

## 사전 준비

1. Logic Pro 12.2 실행 중
2. 신규 프로젝트 생성 (BPM 120, 4/4)
3. region 최소 1개 (drum loop 또는 빈 audio 트랙 region) — 빈 프로젝트면 dialog disabled
4. AppleScript Editor 또는 터미널 `osascript` 가용

## 시나리오

### S1 — 영문 빌드 (영문 IME)

System Settings → Language & Region → Apps → Logic Pro → English. Logic 재시작.

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

**기대**: Logic 좌상단 Position display가 `146.4.4.240` (또는 동일 의미 표시) 으로 변경.

### S2 — 한글 빌드 (한글 IME OFF — 영문 입력 모드)

System Settings → Language & Region → Apps → Logic Pro → Korean. Logic 재시작. 메뉴 입력기 영문 모드 (Caps Lock OFF / 한영 키 영문).

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

**기대**: 동일.

### S3 — 한글 빌드 (한글 IME ON — Hangul mode)

S2 환경에서 **한영 키를 눌러 한글 입력 모드 ON**. 시스템 메뉴바 입력기 표시가 "한"으로 바뀐 상태에서 동일 AppleScript 실행.

**기대 (가설)**: `keystroke "146.4.4.240"` 의 `.` 가 Hangul mode 에서 누락 또는 다른 문자로 변환 → playhead가 부정확한 위치로 이동 또는 dialog가 입력 reject.

**관측 필요 항목**:
- Position display 결과 (`146.4.4.240` vs `1464240` vs `146` vs error)
- dialog 가 keystroke 받았는지 (close 또는 reject)
- 좌하단 status bar 메시지

## 결과 기록 양식

```
S1 영문빌드 / 영문 IME:        [PASS / FAIL]
   - Position display 결과: __________
   - 노트: __________

S2 한글빌드 / 영문 IME:        [PASS / FAIL]
   - Position display 결과: __________
   - 노트: __________

S3 한글빌드 / 한글 IME ON:     [PASS / FAIL]
   - Position display 결과: __________
   - 노트: __________
```

## 분기 기준

| 결과 | 다음 조치 |
|------|----------|
| 3/3 PASS | implementation Tier 0 — 단순 `keystroke "B.B.D.T"` 사용 가능. T1-T10 진행 |
| S1+S2 PASS, S3 FAIL | implementation Tier 1 — pasteboard paste 사용 (NSPasteboard.general save+restore). T1-T10 진행 |
| S1 PASS, S2/S3 FAIL | implementation Tier 2 — input source 강제 ABC 전환 + 복원. PRD v0.5 (위험 mitigation 보강) |
| S1 FAIL | implementation Tier 3 — `CGEventKeyboardSetUnicodeString` Unicode injection. PRD v0.5 (Apple API + 채널 분리) |
| 모두 FAIL | NG10 fix 불가능. v3.2 scope 축소 — provenance만 ship, navigation은 v3.3 보류 |

## 부수 검증 (필수 아님 권장)

- AppleScript `keystroke` 가 IME 활성 상태에서 어떤 동작을 하는지 console.app 로그 확인
- `do shell script "osascript -e 'do shell script ...'"` 으로 keystroke 우회 테스트
- Logic 좌상단 Position display의 정확한 형식 (`bar.beat.div.tick` vs `bar . beat . div . tick`)

## Acceptance Criteria

- **AC-T0.1**: 위 3 시나리오 결과를 `docs/live-verify-v3.2.0.md` Tier 2 에 영구 기록
- **AC-T0.2**: 분기 결정을 PRD v0.4 → v0.5 에 반영 (또는 v0.4 유지 + 결과 추가)
- **AC-T0.3**: T0 결과 없이 T1-T10 진행 금지 (release gate)

## Why this is a release gate

PRD v0.1 이 가정한 "AppleScript keystroke 4-component native input" 이 검증되지 않음. Boomer P0 (round 1) 이 정확히 이 점을 지적. 실측 없이 implementation 시작 시 — IME 환경에서 silently 잘못된 위치로 이동하는 새로운 NG 만들 가능성 있음 (v3.1.5/6/7 false-positive cycle 패턴 재발).
