# T8 — TROUBLESHOOTING + CHANGELOG + docs/API.md + README + Version Bump 3.2.0

**Status**: Todo
**의존성**: T1-T7
**Size**: M
**PRD**: §6 (T8 expanded scope), Boomer round 2 P2

## 변경 대상

| 파일 | 변경 내용 |
|------|----------|
| `Sources/LogicProMCP/Server/ServerConfig.swift` | `serverVersion = "3.2.0"` |
| `Formula/logic-pro-mcp.rb` | `version "3.2.0"` (sha256은 release.sh가 patch) |
| `manifest.json` | version `3.2.0` |
| `Scripts/install.sh` | version label `3.2.0` |
| `README.md` | Status 섹션 v3.2.0 entry 추가 |
| `CHANGELOG.md` | `## [3.2.0] — 2026-MM-DD` 추가 |
| `docs/TROUBLESHOOTING.md` | `goto_marker` 정확도 + provenance 항목 추가 |
| `docs/API.md` | `MarkerState` schema (positionSource 포함) + `logic_navigate.goto_marker` 라우팅 + extras 명시 + `logic_transport.goto_position` 4-component 동작 명세 |

## docs/API.md 핵심 변경

기존 (line 369-371):
```ts
// MarkerState (polled into cache, also available in logic://project/info)
{ id: int, name: string, position: string }
```

→
```ts
// MarkerState (v3.2 schema)
{
  id: int,
  name: string,
  position: string,                              // "bar.beat.div.tick" canonical
  position_source: "parser"|"fallback"|"unknown",  // provenance
  is_canonical: boolean                          // derived: position_source == "parser"
}
```

`goto_marker { name: ... }` 라우팅 행:
```
| `goto_marker` | `{ name: string }` or `{ index: int }` | text | By name: cache lookup → transport.goto_position (4-component dialog/slider). 마커가 fallback/unknown provenance 면 응답 extras에 `marker_position_uncertain: true` 추가 |
```

`goto_position` 라우팅 행 (line 72) — 4-component dialog path 정확도 명시 (boomer P2-2 fix: 정확한 표기 — `bar.beat.div.tick` 1..9999 / 1..16 / 1..16 / 1..999):
```
| `goto_position` | `{ bar: int }` (1..9999) or `{ position: string }` — `"bar.beat.div.tick"` (1..9999, 1..16, 1..16, 1..999) 정밀 sub-bar nav or `"HH:MM:SS:FF"` SMPTE (CGEvent fallback) | text | Accessibility (4-component dialog → bar+beat slider partial) → CGEvent (timecode) |
```

## CHANGELOG entry 초안

```markdown
## [3.2.0] — 2026-MM-DD

**v3.1.11 NG10 closed + Boomer P2-3 closed.** `goto_marker` 가 마커의 정확한
sub-bar 위치(`bar.beat.div.tick`)에 도달하며, marker `position` field는 parser
성공/fallback 출처를 머신 가독으로 surface.

### Changed

- `transport.goto_position` AX channel: 4-component dialog 입력 (기존 1-component bar만)
- `MarkerState` schema: `position_source: "parser"|"fallback"|"unknown"` + derived `is_canonical: boolean` 추가
- `goto_marker`: fallback/unknown 마커 라우팅 시 extras `marker_position_uncertain: true` + `marker_position_source` surface

### Codable backward compat

v3.1.x cache snapshot 디코딩 시 `position_source` 누락 → `.unknown` (false provenance 차단). 신규 marker는 항상 `.parser` 또는 `.fallback`.

### Implementation

- `AccessibilityChannel.parseFourComponentPosition` helper (caller validation)
- `gotoPositionViaDialog` 시그니처: `bar: Int` → `position: FourComponentPosition`
- `gotoPositionViaSliderPartial` 신규 — bar+beat partial, extras `precision: "bar_beat"`
- IME mitigation: T0 live spike 결과에 따라 Tier 0/1/2/3 (자세한 내용 docs/live-verify-v3.2.0.md)

### Tests

1064 → 1074+ PASS. E1-E13 매트릭스 + 3 cross-ticket E2E + Codable backward compat.

### Behavior change

없음 — back-compat 가짜 주장 제거 (1-component position은 v3.1.x 부터 dispatcher가 거부했으며 v3.2도 동일).

### Honest deferred

- Logic 11.x AX 표면 — 12.x primary, 11.x follow-up
- Timecode 정밀 nav — 별도 `mmc.locate` 호출 필요 (v3.2 자동 라우팅 추가 안 함)
```

## README Status 추가

```markdown
**v3.2.0** (2026-MM-DD) — `goto_marker` sub-bar 정확도 (NG10 closed) + Marker provenance (Boomer P2-3 closed). `MarkerState` schema에 `position_source` + `is_canonical` 추가. v3.1.x cache snapshot은 `.unknown` 으로 decode (backward compat). 자세한 내용 [CHANGELOG §3.2.0](CHANGELOG.md#320--2026-mm-dd).
```

## Acceptance Criteria

- **AC-T8.1**: 4 version artifact (`ServerConfig`, `Formula`, `manifest`, `install.sh`) 모두 `3.2.0`
- **AC-T8.2**: `testServerVersionMatchesPackagingArtefacts` PASS
- **AC-T8.3**: README Status 섹션에 v3.2.0 entry 첫 줄
- **AC-T8.4**: CHANGELOG `## [3.2.0]` 섹션 추가, Unreleased 섹션 비움
- **AC-T8.5**: docs/API.md `MarkerState` schema 갱신 + `goto_marker` 라우팅 행 갱신 + `goto_position` 행 갱신
- **AC-T8.6**: TROUBLESHOOTING `position_source` 항목 + `goto_marker` 정확도 항목 추가
- **AC-T8.7**: 한글 주석/한글 마크다운 일관성 (영문 보충 OK — 사용자 directive는 코드 주석 한글)
- **AC-T8.8**: 4 version artifact (ServerConfig + Formula + manifest + install.sh)에 `3.2.0` 정확히 명시 — historical refer (CHANGELOG의 v3.1.11 entry 등)는 보존 (boomer P2-2 fix: grep AC scope 제한)

## Out of Scope

- live-verify runbook = T9
- release 실행 = T10
