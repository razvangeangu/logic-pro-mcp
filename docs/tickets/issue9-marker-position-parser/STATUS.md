# Pipeline Status: Issue #9 Marker Position Parser

**PRD**: docs/prd/PRD-issue9-marker-position-parser.md (v0.3 Approved)
**Size**: M (변경 범위) / XL (review depth — 4-agent × 3 phases)
**Current Phase**: 7 (Release Done)
**Started**: 2026-05-07
**Released**: 2026-05-07 — v3.1.11

## Tickets

| Ticket | Title | Status | Review | Notes |
|--------|-------|--------|--------|-------|
| T1 | parser strict 4-component fix (한글 주석) | Done | PASS | body 15 lines + ASCII narrow strict (boomer P2-1) |
| T2 | parameterized test matrix (28 cases) | Done | PASS | 8 valid + 20 invalid (boomer +3 부호 prefix) |
| T3 | 통합 회귀 테스트 (영문 trailing-dot + 한글 whole-bar) | Done | PASS | tester WARN G3 양쪽 보장 |
| T4 | TROUBLESHOOTING 13 locales + Window 메뉴 부재 | Done | PASS | Boomer P1-2 |
| T5 | README + CHANGELOG v3.1.11 + version bump | Done | PASS | 모든 artifact 동기 |
| T6 | live-verify-v3.1.11.md (3-tier runbook) | Done | PASS | 영문 12.2 절차 + Tier 3 NG 명시 |
| T7 | release v3.1.11 + Issue #9 정중 감사 댓글 | Done | PASS | 11 원칙 + 사용자 보고 |

## Review History

| Phase | Round | Verdict | P0 | P1 | P2 | Notes |
|-------|-------|---------|----|----|----|-------|
| 2 | 1 | REQUEST CHANGES | 3 | 5 | 3 | Strategist + Guardian + Boomer |
| 2 | 2 | ALL PASS (PRD v0.3) | 0 | 0 | 0 | Lenient 폐기 + 13 locales 통합 |
| 4 | 1 | ALL PASS (티켓 v1.1) | 0 | 0 | 2 | Tester WARN(G3 통합 회귀)+Guardian(grep AC 추가) — 모두 적용 |
| 6 | 1 | ALL PASS (boomer codex) | 0 | 0 | 4 | P2-1(부호 prefix 차단) 본 릴리스에 반영. P2-2/3/4는 v3.2 후속 |

## Final Outcome

- **Tests**: 1064 / 1064 PASS (baseline 1062 in v3.1.10) — net +28 case 매트릭스
- **Build**: `swift build -c release` clean (0 warnings)
- **Behavior change**: `"17 2"` v3.1.10 valid → v3.1.11 invalid (lenient 폐기)
- **Sub-bar nav (NG10)**: cache 정확성까지만 scope. Navigation 정확도는 v3.2 PRD 분리
- **Korean comments only** (11 원칙 #9): parser + 신규 테스트 모두 한글
- **Parser body**: 15 lines (AC-4.6 ≤ 20 충족)
- **AC-4.2 신규 TODO/FIXME**: 0
- **Boomer P2-1 추가 fix**: `Int(_:)` Swift 리터럴 우회 차단 (`+1`/`-1`/leading prefix → ASCII 0-9 char-set check 필수)
