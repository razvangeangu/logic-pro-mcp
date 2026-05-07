# Pipeline Status: v3.2 Sub-Bar Nav (NG10) + Marker Provenance

**PRD**: docs/prd/PRD-v32-sub-bar-nav.md (v0.4 — Boomer ALL PASS round 4)
**Size**: L
**Current Phase**: 5 (TDD 구현) — **BLOCKED on T0 live spike (Isaac human-in-the-loop)**
**Started**: 2026-05-07

## Tickets

| Ticket | Title | Size | Status | Review | 의존성 |
|--------|-------|------|--------|--------|--------|
| **T0** | **Live spike (release gate)**: 4-component dialog 검증 + IME 3 시나리오 | S (수동) | **Blocked — needs Isaac + Logic Pro** | - | — |
| T1 | `parseFourComponentPosition` helper (caller 입력 추출) | S | Todo | - | T0 PASS |
| T2 | `gotoPositionViaBarSlider` 4-comp 확장 + AppleScript runner test seam | M | Todo | - | T1 |
| T2a | IME mitigation Tier 1 (pasteboard) — conditional T0 S3 FAIL | S | Todo | - | T0, T2 |
| T2b | IME mitigation Tier 3 (CGEventKeyboardSetUnicodeString) — conditional T0 S1 FAIL | M | Todo | - | T0, T2 |
| T3 | `MarkerState.positionSource` enum + Codable backward compat | S | Todo | - | — |
| T4 | `extractMarkerPosition` 양쪽 fallback site (legacy + 12.2 listWindow) `.fallback` 마킹 | S | Todo | - | T3 |
| T5 | `logic://markers` envelope `position_source` + derived `is_canonical` (Encodable DTO) | S | Todo | - | T3 |
| T6 | `goto_marker` HC top-level extras merge (`marker_position_uncertain`+`marker_position_source`) | S | Todo | - | T2, T4 |
| T7 | parameterized 매트릭스 + 통합 회귀 테스트 (1074+ tests) | M | Todo | - | T1, T2, T3, T4, T5, T6 |
| T8 | TROUBLESHOOTING + CHANGELOG + docs/API.md + README + version bump 3.2.0 | M | Todo | - | T7 |
| T9 | live-verify-v3.2.0 runbook | S | Todo | - | T7 |
| T10 | Release v3.2.0 + final report | S | Todo | - | T8, T9 |

## Review History

| Phase | Round | Verdict | P0 | P1 | P2 | Notes |
|-------|-------|---------|----|----|----|-------|
| 2 | 1 | REQUEST CHANGES | 1 | 4 | 2 | Boomer codex BOOMER-6 |
| 2 | 2 | REQUEST CHANGES | 0 | 2 | 1 | SMPTE routing fact + Tier 3 API + docs scope |
| 2 | 3 | REQUEST CHANGES | 0 | 1 | 1 | E11 동기화 + 11 원칙 API list |
| 2 | 4 | **ALL PASS (PRD v0.4)** | 0 | 0 | 0 | Boomer codex 최종 |
| 4 | 1 | REQUEST CHANGES | 0 | 5 | 2 | cyclic deps / IME 티켓 부재 / T2 test seam / T4 양쪽 site / T6 HC shape / T5 manual concat / T8 typo+grep |
| 4 | 2 | REQUEST CHANGES | 0 | 1 | 2 | T2 appleScriptRunner 누락 / T5 Refactor 모순 / T2 stale T2.1 ref |
| 4 | 3 | **ALL PASS (티켓 v1.1)** | 0 | 0 | 0 | T2a/T2b 추가 + 모든 round 2 fix 적용 |
| 6 | | | | | | (최종 전수 리뷰 예정 — T0 PASS 후) |

## Blockers

**T0 Live Spike** is a release gate per PRD §3.4:

```
T0 절차 (Logic Pro 12.2 실기기):
1. 빈 프로젝트 + region 1개 → 탐색 → 이동 → 위치… 수동 오픈
2. 한글 IME ON / 영문 빌드 / 영문 빌드 + 한글 IME 3가지에서
   AppleScript keystroke "146.4.4.240" + return 시도
3. 각각에서 playhead가 정확한 sub-bar에 도달하는지 확인
4. 3/3 PASS 시에만 implementation 진행
5. 1+ FAIL 시 Tier 1 (pasteboard) 또는 Tier 3 (Unicode injection) 선택 후 PRD v0.5
```

**Why Isaac**: AppleScript dialog interaction은 Logic Pro 실행 + 사용자 입력 필요. 자동화 불가능 (육안 확인 필수).

## Outcome (예상)

- 1064 → 1074+ tests PASS
- `goto_marker { name: "VOCALS" }` 라이브 → 정확한 sub-bar 도달
- `logic://markers` 응답 `position_source` + `is_canonical` 100% 포함
- v3.1.11 NG10 closed
- Boomer P2-3 closed
- Version 3.2.0 (minor bump — new nav capability)
