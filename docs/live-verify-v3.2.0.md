# Live Verification Runbook — v3.2.0 (Marker Provenance, NG10 Deferred)

**검증 시점**: v3.2.0 release 직전 + T0 spike 결과 영구 기록.
**Scope**: marker `position_source` provenance + `goto_marker` uncertainty surfacing.
**Honest Deferred**: NG10 (sub-bar navigation 정확도) — Logic 12.2 위치 dialog 4-segment AXSlider 구조로 인해 v3.2.0 approach 실패. v3.3에서 raw slider value mapping 분석 필요.

---

## T0 Spike 결과 — 영구 기록 (2026-05-07)

### 환경
- macOS 25.3.0 (Darwin)
- Logic Pro 12.2 한글 빌드
- Project "무제 20 - 트랙" 1 track / 1 region
- IME: 시스템 기본 (한글 입력 모드 가능성)

### S2 시나리오 (한글 빌드 + 시스템 IME)

```
1. transport.goto_position bar=1 → success requested 1.1.1.1
2. AppleScript: keystroke "146.4.4.240" + return → spike_sent
3. logic://transport/state 4초 후 read → position: "129.1.1.1"
```

**FAIL** — 목표 `146.4.4.240` 과 다른 위치 `129.1.1.1`로 이동. sub-bar 부분(beat/div/tick) 모두 1로 reset.

### S2 검증 — 단순 1-component 시도 (`keystroke "146"`)

같은 baseline 후 `keystroke "146"`만 시도. 결과 동일하게 `position: "129.1.1.1"` — playhead 변경 없음 (이미 129.1.1.1에 있는 상태에서 dialog가 효과 없이 닫힘).

→ **dialog input 자체가 keystroke 처리 안 됨**. main window keyboard shortcut 우회 가능성도 존재.

### Dialog AX 구조 enum (실측)

```
window "위치로 이동"
  AXGroup desc=01:04:16:00.00          ← SMPTE "현재" (HH:MM:SS:FF.SUB)
    AXSlider × 5 segments              raw value ~1.85E+8 (internal encoding)
  AXGroup desc=\t129\t1\t1\t1          ← bar.beat.div.tick "현재"
    AXSlider × 4 segments              raw value ~2.27E+15
  AXGroup desc=01:04:16:00.00          ← SMPTE "신규"
    AXSlider × 5 segments
  AXGroup desc=\t129\t1\t1\t1          ← bar.beat.div.tick "신규" focused=true
    AXSlider × 4 segments              raw value ~2.27E+15 (segment별 raw 표현)
  AXButton × 2                          ← 확인 / 취소
  AXStaticText × 3                      ← "신규:" "현재:" "위치로 이동"
```

### 가정이 깨진 부분 (PRD §3.4 근거)

| PRD v0.4 가정 | 실측 결과 |
|---------------|----------|
| Dialog가 단일 텍스트 input | ❌ 4-segment AXSlider 구조 (bar/beat/div/tick 별개) |
| `keystroke "B.B.D.T"` 가 native 4-component 입력 | ❌ keystroke가 segment에 도달 안 함 |
| Logic 좌상단 Position display는 직접 cache surface | ✅ `logic://transport/state` 정확히 surface |
| `gotoPositionViaDialog` AppleScript로 dialog 자동화 가능 | ✅ dialog 열기는 정상, 입력은 실패 |

### AXSlider 직접 value set 시도

```applescript
set value of (item 1 of sliders) to 146  → ERROR: AppleEvent 처리 구조 실패
```

nested AppleScript 표현 한계 + slider raw value (1.85E+8 / 2.27E+15) 와 displayed value(146/4/4/240) 매핑 미해독. v3.3 분석 과제.

### 결정 (v3.2.0 scope 축소)

- **NG10 (sub-bar nav 정확도)**: v3.3 PRD로 honest deferred. dialog AXSlider 4-segment raw value mapping 깊이 분석 필요.
- **v3.2.0 ship scope**: marker provenance만 — `MarkerState.positionSource` enum + `logic://markers` envelope + `goto_marker` uncertainty extras.
- **Why ship at all**: 외부 사용자(`thomas-doesburg` 등)가 fallback marker 인지 가능 → caller 책임 surface. v3.1.5-7 false-positive cycle 재발 방지에 즉시 효용.

---

## Tier 1 — Automated (CI / dev box)

```bash
swift test --no-parallel
# → 1064 + 신규 ≥ 8 = 1072+ PASS

swift build -c release
# → 0 warnings

swift test --no-parallel --filter MarkerState
# → Codable round-trip + legacy snapshot decode (.unknown) PASS

swift test --no-parallel --filter testServerVersionMatchesPackagingArtefacts
# → version 3.2.0 모든 artifact 동기 검증

brew test logic-pro-mcp
# → exit 0
```

## Tier 2 — Live (Logic Pro 12.2 실기기)

### 2.1 Marker provenance — `logic://markers` envelope

```bash
# 1. Logic Pro Marker List 윈도우 열기 + 마커 1개 추가
# 2. Marker List에서 position을 비-정상 값으로 편집 (예: "abc") — parser fail induce
# 3. logic_system refresh_cache
# 4. logic://markers read
```

기대:
- 정상 마커: `{"position": "1.1.1.1", "position_source": "parser", "is_canonical": true}`
- parser 실패 마커: `{"position": "1.1.1.1", "position_source": "fallback", "is_canonical": false}`

### 2.2 `goto_marker` uncertainty surfacing

`goto_marker { name: "[fallback marker name]" }` → 응답 extras에 `marker_position_uncertain: true` + `marker_position_source: "fallback"` 포함.

정상(parser) marker 호출 시 uncertainty extras 부재 — 기존 응답 그대로.

### 2.3 Codable backward compat

기존 `~/.logic-pro-mcp/cache.json` (v3.1.x snapshot) 로드 → marker `positionSource` missing → `.unknown` decode → `is_canonical: false`. crash 0.

---

## Tier 3 — NG / Honest Disclosure

| NG | 내용 |
|----|------|
| **NG10** | **Sub-bar navigation 정확도 v3.2.0에서 closed 안 됨**. `goto_marker { name: "VOCALS" }` 가 cache의 `"146.4.4.240"`을 정확히 surface하지만, AX channel은 첫 dot-component(bar 146)만 navigate. v3.1.11 동작과 동일. v3.3 PRD에서 dialog AXSlider 4-segment raw value mapping 분석 후 closure 예정. |
| NG-v32-1 | Logic 11.x AX 표면 미검증 — 12.x primary |
| NG-v32-2 | Timecode 정밀 nav는 별도 `mmc.locate` (v3.2 자동 라우팅 추가 X) |
| NG-v32-3 | provenance `.unknown` 케이스 — legacy cache snapshot에서만 발생. 신규 marker는 `.parser` / `.fallback` 명확 |

---

## When to update this runbook

- v3.3에서 NG10 closure 시도 — slider raw value mapping 결과 추가
- 신규 locale 보고 — Tier 2.1 표 행 추가
- Logic 13/14 출시 — 전체 재실행
