# PRD — v3.2 Sub-Bar Navigation (NG10) + Marker Provenance (Boomer P2-3)

**Status**: Draft (v0.4 — boomer round 3 P1+P2 통합)
**Size**: L
**Owner**: Isaac
**Started**: 2026-05-07
**Driving issues**:
- v3.1.11 NG10 (Guardian P0-1) — `gotoPositionViaBarSlider` 첫 dot-component만 소비
- v3.1.11 Boomer P2-3 — Marker fallback position(`\(index+1).1.1.1`) 머신 가독 provenance 없음

---

## 1. Goal

`goto_marker { name: "VOCALS" }` 가 cache의 정확한 `"146.4.4.240"`에 **실제로** 도달하도록 한다. v3.1.11은 cache 정확성까지만 scope. v3.2는 navigation 정확성을 closes the loop.

추가로, marker `position` field가 parser 성공/fallback 인지 머신 가독으로 surfacing 한다 — `goto_marker`가 fallback position에 라우팅하기 전 caller가 인지 가능.

## 2. Non-Goals

- Logic 11.x AX 표면 — out of scope (12.x primary). 11.x는 follow-up.
- Timecode (HH:MM:SS:FF) sub-frame nav — 별도 PRD (CoreMIDI MMC scope).
- 기존 parser 변경 — v3.1.11 strict 4 정책 유지. v3.2는 **caller side**만 변경.
- Empty-project navigation full-precision — Logic dialog가 disabled. slider fallback에서 partial(bar+beat) 처리.

## 3. Background

### 3.1 v3.1.11 종착점 (cache 정확성)

```
logic://markers → MarkerState{ id, name, position: "146.4.4.240" }
```

`position`은 두 가지 경로:
1. **parser success**: `parseMarkerListPosition("146 4 4 240.")` → `"146.4.4.240"` (canonical)
2. **parser fallback**: `nil` 반환 → caller `\(index+1).1.1.1` 사용 (manufactured but honest)

caller가 둘을 구별 못 함 → `goto_marker`가 fallback position에 라우팅 시 silently 잘못된 bar로 이동.

### 3.2 v3.1.11 nav 한계 (NG10)

```swift
// Sources/LogicProMCP/Channels/AccessibilityChannel.swift:2206-2208
let parts = pos.split(separator: ".")
if let first = parts.first, let b = Int(first) {
    targetBar = b
}
```

`"146.4.4.240"` 입력 시 `targetBar = 146`만 set. beat=4, div=4, tick=240 무시. Slider path는 bar slider만 set + beat slider를 1로 reset (whole-bar 의도).

### 3.3 TransportDispatcher 현재 검증 (코드 재확인)

`Sources/LogicProMCP/Dispatchers/TransportDispatcher.swift:150` `isValidPositionString` — 정확히 4-component bar.beat.sub.tick (bar 1..9999, beat 1..16, sub 1..16, tick 1..999) **또는** SMPTE만 허용. 1-component `"146"` 거부. `bar` 정수 입력은 별도 분기 (line 90).

→ **PRD v0.2 수정**: 1-component back-compat AC 제거. 기존 dispatcher가 거부 → 그대로 거부 유지.

### 3.4 Logic 12.2 dialog 동작 (T0 spike — 검증 게이트)

`탐색 → 이동 → 위치…` (`Navigate → Go To → Position…`) dialog가 `bar.beat.div.tick` 4 컴포넌트 텍스트 입력을 받는지 **여부** 자체가 미검증.

**P0 (Boomer)**: 본 가정 위에 implementation 시작 금지. **T0 live spike**가 release gate.

T0 spike 절차 (구현 전 필수):
1. 빈 프로젝트 + region 1개 → `탐색 → 이동 → 위치…` 수동 오픈
2. 한글 IME ON / 영문 빌드 / 영문 빌드 + 한글 IME 3가지 시나리오에서 keystroke `"146.4.4.240"` + return 시도
3. 각각에서 playhead가 정확한 sub-bar(bar 146 / beat 4 / div 4 / tick 240)에 도달하는지 육안 + Logic 좌상단 Position display 확인
4. **3가지 모두 PASS 시에만 v3.2 implementation 진행**. 1개라도 FAIL 시 → IME mitigation 강화 (P1-1) 또는 nav scope 축소

### 3.5 IME mitigation (P1-1 강화)

AppleScript `keystroke "."` 가 한글 IME Hangul mode에서 ASCII punctuation 누락 가능. 단순 `keystroke 분할`은 같은 input source 경로 → 효과 없음 (Boomer 정확).

**3-tier mitigation** (v0.3 — Tier 3 정확화):
1. **Tier 1 (preferred)**: pasteboard paste — `"146.4.4.240"`을 NSPasteboard에 set + `keystroke "v" using command down`. IME 우회. 부작용: 사용자 클립보드 — save+restore 패턴 필수.
2. **Tier 2 (fallback)**: AppleScript `tell application "System Events" to set selectedInputSource to ABC` 강제 후 keystroke + 원래 input source 복원. 부작용: 사용자 input source 잠시 변경 (~100ms). 한글 입력 중 사용자 시각 거슬림 가능.
3. **Tier 3 (last resort, real Unicode)**: `CGEventKeyboardSetUnicodeString` API — 진짜 IME-agnostic Unicode event injection. `CGEvent` 생성 후 `CGEventKeyboardSetUnicodeString(event, length, &chars)` 호출. 기존 `CGEventChannel.keyStroke(for: ".")` 의 keycode 47 방식과 다름 — keycode는 layout-dependent, Unicode injection은 OS-layer string injection. 신규 helper `CGEventChannel.postUnicodeString(_ s: String, pid: pid_t)` 추가 필요.

> 기존 `CGEventChannel.keyStroke(for: ".")` (keycode 47) 는 ASCII 입력 layout 기준이며 IME 활성 시 동작 미보장. v3.2 신규 Tier 3는 별도 API.

T0 spike 결과에 따라 Tier 1/2/3 선택. PRD v0.3에서 확정.

## 4. Functional Requirements

### 4.1 Navigation 정확도 (FR-1)

`transport.goto_position { position: "B.B.D.T" }` 호출 시 (TransportDispatcher 검증 통과 후 라우팅):

- **AC-1.1**: `position`이 4-component canonical (`"146.4.4.240"`, bar 1..9999, beat 1..16, sub 1..16, tick 1..999) → 4 컴포넌트 모두 dialog로 전달, playhead가 정확한 sub-bar 위치에 도달. **본 AC는 §3.4 T0 spike PASS를 전제**.
- **AC-1.2 [REMOVED in v0.2]**: 1-component back-compat — TransportDispatcher가 이미 거부. 가짜 back-compat 제거.
- **AC-1.3**: `position`이 timecode (`"00:01:30:00"`) — TransportDispatcher 검증 통과 후 ChannelRouter `[.accessibility, .mcu, .coreMIDI, .cgEvent]` 순회. AX는 timecode 미지원 → AX channel error → MCU channel error (no `transport.goto_position` mapping) → CoreMIDI channel reject → CGEvent CGEventChannel keystroke (existing). 결과: 사용자에게 timecode `"00:01:30:00"` 자동 keystroke 전달. SMPTE 정밀 nav는 별도 `mmc.locate` 호출 필요 (현재 별도 op). v3.2에서 자동 라우팅 추가 안 함 (out-of-scope).
- **AC-1.4**: `bar` 정수 입력 — 호환성 유지 (기존 caller). bar.1.1.1로 dialog 전달 (기존 동작).
- **AC-1.5**: dialog disabled (empty project) → slider fallback. bar slider + beat slider까지 set. div/tick 무시. Honest Contract `readback_unavailable` + extras `precision: "bar_beat"` 명시 (boomer P1-3 — 신규 reason 추가 안 함).
- **AC-1.6**: dialog timeout / DIALOG_NOT_READY → State C error. slider fallback 시도.

### 4.2 입력 검증 (FR-2)

- **AC-2.1**: TransportDispatcher `isValidPositionString` 가 1-3 / 5+ component 거부 (기존 동작 유지). v3.2 추가 검증 불필요.
- **AC-2.2**: bar 1..9999, beat 1..16, sub 1..16, tick 1..999 (기존). 0 또는 음수 거부.
- **AC-2.3**: 비-ASCII digit 거부 (기존 — `Int(_:)` failable 사용 중. v3.1.11 parser와 일관).
- **AC-2.4**: AX channel `gotoPositionViaBarSlider` 가 4 컴포넌트 모두 추출하지만 AC-2.1 검증된 입력만 도달 → guard 단순화.

### 4.3 Marker provenance (FR-3 — Boomer P1-2 + P2-1)

- **AC-3.1**: `MarkerState` 에 `positionSource: PositionSource` field 추가 (enum):
  ```swift
  enum PositionSource: String, Codable, Sendable {
      case parser    // canonical — parseMarkerListPosition success
      case fallback  // manufactured — \(index+1).1.1.1
      case unknown   // legacy snapshot pre-v3.2 — boomer P1-2 false provenance 차단
  }
  ```
- **AC-3.2**: `logic://markers` JSON에 `position_source` (snake_case JSON, camelCase Swift) surface.
- **AC-3.3**: `is_canonical: Bool` JSON-only **derived** field — `position_source == "parser"` 일 때 true. **저장 X** (boomer P2-1).
- **AC-3.4**: 기존 `position` field 동작 유지 (back-compat). Source enum만 신규 저장.
- **AC-3.5**: Codable backward-compat — 기존 v3.1.x cache snapshot 디코딩 시 `position_source` missing → `.unknown` 으로 디코드 (boomer P1-2 — `.parser` 기본값은 거짓 provenance). 신규 마커는 항상 `.parser` 또는 `.fallback` 명시.
- **AC-3.6**: `goto_marker`가 `position_source ∈ {.fallback, .unknown}` 마커 라우팅 시 응답 extras에 `marker_position_uncertain: true` + `marker_position_source: "fallback"|"unknown"` surface (boomer P2-2 — JSON merge 명시).

### 4.4 코딩 규약 (FR-4 — 11 원칙 유지)

- **AC-4.1**: 신규/수정 코드 한글 주석만 (English 주석 추가 금지).
- **AC-4.2**: 신규 TODO/FIXME/XXX 0건 (grep verify).
- **AC-4.3**: parser 변경 0건 — v3.1.11 strict 4 정책 유지. caller side만 수정.
- **AC-4.4**: SOLID/SRP — `parseFourComponentPosition` 별도 함수로 분리 (parser 함수와 다른 책임 — caller 입력 추출).
- **AC-4.5**: 컴팩트 — 신규 함수 본문 ≤ 25 lines.
- **AC-4.6**: 기존 dialog/slider fallback 동작 회귀 0건 (기존 testServerVersionMatches + dialog tests 모두 PASS).

## 5. Non-Functional Requirements

### 5.1 Performance

- **AC-5.1**: dialog path latency 변화 — Tier 1 pasteboard paste 추가 시 < 100ms 추가. 측정 필수 (live-verify Tier 1).
- **AC-5.2**: Cache schema 추가 field로 인한 serialization 오버헤드 < 5%.

### 5.2 Backward compatibility

- **AC-6.1**: 기존 `transport.goto_position { bar: 5 }` 동작 유지 (TransportDispatcher line 90 분기).
- **AC-6.2 [REMOVED in v0.2]**: 1-component position 거부 유지. back-compat 가짜 주장 제거.
- **AC-6.3**: 기존 `goto_marker` 동작 유지 (cache의 position string 그대로 transport.goto_position에 라우팅).
- **AC-6.4**: MarkerState Codable: `position_source` missing → `.unknown` 으로 decode (기존 cache snapshot 호환 + 거짓 provenance 차단).

### 5.3 Test coverage

- **AC-7.1**: 4-component dialog path unit test (synthetic AppleScript runtime).
- **AC-7.2**: Slider fallback partial(bar+beat) test → `readback_unavailable` + `precision: "bar_beat"` 검증.
- **AC-7.3**: Provenance: parser-success / parser-fail / legacy-snapshot 3 케이스 cache snapshot 테스트.
- **AC-7.4**: `goto_marker { name: "X" }` E2E: cache의 `position_source ∈ {.fallback, .unknown}` 시 응답 extras `marker_position_uncertain: true` 검증.
- **AC-7.5**: 기존 1064 + 신규 ≥ 10 케이스 = 1074+ PASS.
- **AC-7.6**: T0 live spike 검증 결과 `live-verify-v3.2.0.md` Tier 2 에 영구 기록.

## 6. Implementation Plan (티켓 분해 v0.2)

| # | 제목 | Size | 의존성 |
|---|------|------|--------|
| **T0** | **Live spike (release gate)**: 4-component dialog 검증 + IME 시나리오 3가지 | S (수동) | — |
| T1 | `parseFourComponentPosition` helper (caller 입력 추출 — 검증은 dispatcher) | S | T0 PASS |
| T2 | `gotoPositionViaBarSlider` 4-component 확장 (dialog + slider partial fallback) **+ AppleScript runner test seam** | M | T1 |
| T2a | **IME mitigation Tier 1 (pasteboard paste)** — conditional on T0 S3 FAIL | S | T0, T2 |
| T2b | **IME mitigation Tier 3 (CGEventKeyboardSetUnicodeString)** — conditional on T0 S1 FAIL | M | T0, T2 |
| T3 | `MarkerState.positionSource` enum (parser/fallback/unknown) + Codable backward compat | S | — |
| T4 | `extractMarkerPosition` **양쪽 fallback site** (legacy ruler L708 + Logic 12.2 markerListWindow L798-800) `.fallback` 마킹 | S | T3 |
| T5 | `logic://markers` resource envelope에 `position_source` + derived `is_canonical` surface (Encodable DTO + `jsonStringEscape`) | S | T3 |
| T6 | `goto_marker` dispatcher: fallback/unknown marker 라우팅 시 **HC top-level extras merge** (`marker_position_uncertain`+`marker_position_source`) | S | T2, T4 |
| T7 | parameterized 매트릭스 + 통합 회귀 테스트 (1074+ tests) | M | T1, T2, T3, T4, T5, T6 |
| T8 | TROUBLESHOOTING + CHANGELOG + **docs/API.md** (`MarkerState` schema + `goto_marker` extras + `goto_position` 동작 명세) + README + version bump 3.1.11 → 3.2.0 | M | T7 |
| T9 | live-verify-v3.2.0 runbook (T0 결과 영구 기록 + IME 시나리오 + dialog 4-component + slider partial) | S | T7 |
| T10 | Release v3.2.0 + final report | S | T8, T9 |

> **버전 결정**: provenance field가 backward-compat 추가지만, navigation 정확도가 **새 capability**이므로 minor bump (3.1.11 → 3.2.0). Boomer 동의.

## 7. Risks & Mitigations (v0.2)

| Risk | Severity | Mitigation |
|------|---------|-----------|
| AppleScript `keystroke "146.4.4.240"` 가 한글 IME에서 `.` 누락 | High | T0 spike + 3-tier mitigation (§3.5). Tier 1: pasteboard paste, Tier 2: ABC input source 강제, Tier 3: CGEvent Unicode |
| Logic dialog가 4-component 거부 | High | T0 spike에서 1차 검증. 거부 시 nav scope 축소 (PRD v0.3 재작성) |
| Slider div/tick set 시도 시 control bar에 없음 | Low | div/tick set 시도 0회 — 의도적으로 partial. extras `precision: "bar_beat"` 명시 |
| MarkerState Codable 변경 시 기존 cache snapshot 디코딩 실패 | Medium | `.unknown` 기본값 + custom decoder + Codable round-trip test 필수 |
| goto_marker 응답 schema 변경이 기존 클라이언트 깨짐 | Low | extras에만 추가 (기존 field 변경 0). CHANGELOG 명시. 기존 클라이언트 영향 없음 |
| Pasteboard paste 부작용 (사용자 클립보드 덮어쓰기) | Medium | save+restore 패턴 — paste 직전 NSPasteboard.general 읽고 paste 후 0.1s delay 후 복원 |

## 8. Edge Cases (E1-E13 v0.2)

| # | 입력 | 기대 동작 |
|---|------|----------|
| E1 | `position: "146.4.4.240"` | dialog → 정확한 sub-bar |
| E2 | `position: "1.1.1.1"` | dialog → bar 1 시작 |
| E3 | `position: "9999.16.16.999"` | dialog → 최대 bound (수정: tick max 999, sub max 16) |
| E4 | `position: "146"` | TransportDispatcher 거부 (기존 동작). E5 동일 |
| E5 | `position: "146.4"` | TransportDispatcher 거부 (기존) |
| E6 | `position: "146.4.4"` | TransportDispatcher 거부 (기존) |
| E7 | `position: "146.4.4.240.1"` | TransportDispatcher 거부 (기존) |
| E8 | `position: "0.1.1.1"` | TransportDispatcher 거부 (기존 — bar 1..9999) |
| E9 | `position: "10000.1.1.1"` | TransportDispatcher 거부 (기존) |
| E10 | `position: "146.17.4.240"` | TransportDispatcher 거부 (기존 — beat 1..16) |
| E11 | `position: "00:01:30:00"` | TransportDispatcher 통과 → ChannelRouter AX/MCU/CoreMIDI reject → CGEvent keystroke fallback (기존). 정밀 SMPTE는 별도 `mmc.locate` 필요 |
| E12 | `bar: 146` (구 caller) | dialog → bar 146 (기존) |
| E13 | empty project (dialog disabled) | slider fallback bar+beat partial. State B `readback_unavailable` + `precision: "bar_beat"` |

## 9. 11 원칙 매핑 (Isaac directive)

| # | 원칙 | 적용 |
|---|------|------|
| 1 | 실리콘밸리 0.1% | T0 spike + 4-agent × 3 review phases (PRD + 티켓 + 최종) + 라이브 e2e |
| 2 | Apple 수준 | Foundation + AppleScript + NSPasteboard + CGEventKeyboardSetUnicodeString (Apple 공식 IME-agnostic API). 순수 함수 분리, 본문 ≤ 25 lines |
| 3 | 0.1% 엣지케이스 0 | E1-E13 + parameterized 매트릭스 + IME 3 시나리오 |
| 4 | 오버엔지니어링 금지 | back-compat 가짜 AC 제거 (boomer P1-4); div/tick slider 추가 0; `is_canonical` derived |
| 5 | 데드코드 0 | grep + git diff verify |
| 6 | 컴팩트 | helper 1 함수, dispatcher 변경 ≤ 30 lines |
| 7 | 표준 레퍼런스 | Swift API Design Guidelines (parseFourComponentPosition 명명) |
| 8 | 주니어 가독성 | 한글 step-by-step 주석 + 3-tier mitigation 명시 |
| 9 | 한글 주석 | 신규/수정 모두 |
| 10 | SOLID/SRP | parser는 AX surface 변환 / 신규 helper는 caller validation / dispatcher는 routing |
| 11 | 컴팩트 | parameterized 매트릭스로 case-by-case 줄이기 + extras 통합 |

## 10. Success Metrics

- 1064 → 1074+ tests PASS
- `swift build -c release` 0 warnings
- `goto_marker { name: "VOCALS" }` 라이브 (Logic 12.2 영문/한글 + IME ON 3 시나리오) → playhead 정확한 sub-bar 도달 (육안 + observed ratio ≥ 95% 매치)
- `logic://markers` 응답에 `position_source` field 100% 포함
- Boomer P2-3 closed
- v3.1.11 NG10 closed
- AC-4.2 grep TODO/FIXME 0건
- T0 live spike 결과 PASS 3/3 (영문 / 한글 IME OFF / 한글 IME ON)

## 11. Approvals

- [x] Boomer BOOMER-6 (PRD v0.1) — REQUEST CHANGES (P0+4P1+2P2)
- [x] Boomer BOOMER-6 (PRD v0.2) — REQUEST CHANGES (2P1+1P2 round 2)
- [x] Boomer BOOMER-6 (PRD v0.3) — REQUEST CHANGES (1P1+1P2 round 3)
- [ ] Boomer BOOMER-6 (PRD v0.4) — 재리뷰 대기
- [ ] Strategist (PRD round 1)
- [ ] Guardian (PRD round 1)
- [ ] Tester (티켓 round 1)
- [ ] Isaac final approval

## Version History

- **v0.1** (2026-05-07): 초안 — 4-agent review 입력 대기.
- **v0.2** (2026-05-07): Boomer BOOMER-6 통합 — P0(T0 spike gate) + P1-1(IME 3-tier mitigation) + P1-2(`.unknown` enum 기본값) + P1-3(`readback_unavailable`+`precision` extras로 reason 추가 회피) + P1-4(1-component back-compat AC 제거) + P2-1(`is_canonical` derived) + P2-2(extras shape 명시).
- **v0.3** (2026-05-07): Boomer round 2 통합 — AC-1.3 SMPTE 라우팅 사실화 (CGEvent fallback 명시 — MCU에 `transport.goto_position` 없음 명기) + Tier 3 IME mitigation `CGEventKeyboardSetUnicodeString` 실제 API 정확화 (기존 keystroke keycode 47과 구분) + T8 scope 확장 (docs/API.md `MarkerState` schema + `goto_marker` extras + `goto_position` 동작 명세 포함).
- **v0.4** (2026-05-07): Boomer round 3 — E11 edge case AC-1.3과 동기화 (CGEvent keystroke fallback 명시) + §9 11 원칙 #2 actual API list (NSPasteboard + CGEventKeyboardSetUnicodeString 추가). ALL PASS 예상.
