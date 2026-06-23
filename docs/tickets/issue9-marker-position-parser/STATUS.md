# Pipeline Status: Issue #9 Marker Position Parser

> Historical record. Current stable evidence is in `README.md`, `CHANGELOG.md`, and `docs/live-verify-v3.7.0.md`; previous stable evidence remains in `docs/live-verify-v3.6.0.md`; this file remains preserved implementation context.

**PRD**: docs/prd/PRD-issue9-marker-position-parser.md (v0.3 Approved)
**Size**: M (change scope) / XL (review depth — 4-agent × 3 phases)
**Current Phase**: 7 (Release Done)
**Started**: 2026-05-07
**Released**: 2026-05-07 — v3.1.11

## Tickets

| Ticket | Title | Status | Review | Notes |
|--------|-------|--------|--------|-------|
| T1 | parser strict 4-component fix | Done | PASS | body 15 lines + ASCII narrow strict (boomer P2-1) |
| T2 | parameterized test matrix (28 cases) | Done | PASS | 8 valid + 20 invalid (boomer +3 sign prefix) |
| T3 | integration regression test (English trailing-dot + Korean whole-bar) | Done | PASS | tester WARN G3 both sides assured |
| T4 | TROUBLESHOOTING 13 locales + Window menu absence | Done | PASS | Boomer P1-2 |
| T5 | README + CHANGELOG v3.1.11 + version bump | Done | PASS | all artifacts synchronized |
| T6 | live-verify-v3.1.11.md (3-tier runbook) | Done | PASS | English 12.2 procedure + Tier 3 NG disclosed |
| T7 | release v3.1.11 + Issue #9 thank-you comment | Done | PASS | 11 principles + user report |

## Review History

| Phase | Round | Verdict | P0 | P1 | P2 | Notes |
|-------|-------|---------|----|----|----|-------|
| 2 | 1 | REQUEST CHANGES | 3 | 5 | 3 | Strategist + Guardian + Boomer |
| 2 | 2 | ALL PASS (PRD v0.3) | 0 | 0 | 0 | Lenient retired + 13 locales integrated |
| 4 | 1 | ALL PASS (ticket v1.1) | 0 | 0 | 2 | Tester WARN(G3 integration regression)+Guardian(grep AC added) — all applied |
| 6 | 1 | ALL PASS (boomer codex) | 0 | 0 | 4 | P2-1(sign prefix block) reflected in this release. P2-2/3/4 → v3.2 follow-up |

## Final Outcome

- **Tests**: 1064 / 1064 PASS (baseline 1062 in v3.1.10) — net +28 case matrix
- **Build**: `swift build -c release` clean (0 warnings)
- **Behavior change**: `"17 2"` v3.1.10 valid → v3.1.11 invalid (lenient retired)
- **Sub-bar nav (NG10)**: cache accuracy only in scope. Navigation precision → v3.2 PRD split
- **Parser body**: 15 lines (AC-4.6 ≤ 20 satisfied)
- **AC-4.2 new TODO/FIXME**: 0
- **Boomer P2-1 additional fix**: `Int(_:)` Swift literal bypass blocked (`+1`/`-1`/leading prefix → ASCII 0-9 char-set check required)
