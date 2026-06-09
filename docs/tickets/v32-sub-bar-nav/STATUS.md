# Pipeline Status: v3.2 Sub-Bar Nav (NG10) + Marker Provenance

> Historical record (2026-06-09 docs refresh): latest production-readiness and live E2E evidence is in `README.md`, `CHANGELOG.md`, and `docs/live-verify-v3.4.6.md`; this file remains preserved implementation context.

**PRD**: docs/prd/PRD-v32-sub-bar-nav.md (v0.4 — Boomer ALL PASS round 4)
**Size**: L
**Current Phase**: 5 (TDD implementation) — **BLOCKED on T0 live spike (Isaac human-in-the-loop)**
**Started**: 2026-05-07

## Tickets

| Ticket | Title | Size | Status | Review | Depends on |
|--------|-------|------|--------|--------|------------|
| **T0** | **Live spike (release gate)**: 4-component dialog validation + IME 3 scenarios | S (manual) | **Blocked — needs Isaac + Logic Pro** | - | — |
| T1 | `parseFourComponentPosition` helper (caller input extraction) | S | Todo | - | T0 PASS |
| T2 | `gotoPositionViaBarSlider` 4-comp extension + AppleScript runner test seam | M | Todo | - | T1 |
| T2a | IME mitigation Tier 1 (pasteboard) — conditional T0 S3 FAIL | S | Todo | - | T0, T2 |
| T2b | IME mitigation Tier 3 (CGEventKeyboardSetUnicodeString) — conditional T0 S1 FAIL | M | Todo | - | T0, T2 |
| T3 | `MarkerState.positionSource` enum + Codable backward compat | S | Todo | - | — |
| T4 | `extractMarkerPosition` both fallback sites (legacy + 12.2 listWindow) `.fallback` marking | S | Todo | - | T3 |
| T5 | `logic://markers` envelope `position_source` + derived `is_canonical` (Encodable DTO) | S | Todo | - | T3 |
| T6 | `goto_marker` HC top-level extras merge (`marker_position_uncertain`+`marker_position_source`) | S | Todo | - | T2, T4 |
| T7 | parameterized matrix + integration regression tests (1074+ tests) | M | Todo | - | T1, T2, T3, T4, T5, T6 |
| T8 | TROUBLESHOOTING + CHANGELOG + docs/API.md + README + version bump 3.2.0 | M | Todo | - | T7 |
| T9 | live-verify-v3.2.0 runbook | S | Todo | - | T7 |
| T10 | Release v3.2.0 + final report | S | Todo | - | T8, T9 |

## Review History

| Phase | Round | Verdict | P0 | P1 | P2 | Notes |
|-------|-------|---------|----|----|----|-------|
| 2 | 1 | REQUEST CHANGES | 1 | 4 | 2 | Boomer codex BOOMER-6 |
| 2 | 2 | REQUEST CHANGES | 0 | 2 | 1 | SMPTE routing fact + Tier 3 API + docs scope |
| 2 | 3 | REQUEST CHANGES | 0 | 1 | 1 | E11 sync + 11 principles API list |
| 2 | 4 | **ALL PASS (PRD v0.4)** | 0 | 0 | 0 | Boomer codex final |
| 4 | 1 | REQUEST CHANGES | 0 | 5 | 2 | cyclic deps / IME tickets missing / T2 test seam / T4 both sites / T6 HC shape / T5 manual concat / T8 typo+grep |
| 4 | 2 | REQUEST CHANGES | 0 | 1 | 2 | T2 appleScriptRunner missing / T5 Refactor inconsistency / T2 stale T2.1 ref |
| 4 | 3 | **ALL PASS (ticket v1.1)** | 0 | 0 | 0 | T2a/T2b added + all round 2 fixes applied |
| 6 | | | | | | (final full review scheduled — after T0 PASS) |

## Blockers

**T0 Live Spike** is a release gate per PRD §3.4:

```
T0 procedure (Logic Pro 12.2 device):
1. Empty project + 1 region → Navigate → Go To → Position… manually opened
2. AppleScript keystroke "146.4.4.240" + return attempted in:
   Korean IME ON / English build / English build + Korean IME — 3 variants
3. Confirm playhead reaches accurate sub-bar in each
4. Proceed to implementation only if 3/3 PASS
5. If 1+ FAIL: choose Tier 1 (pasteboard) or Tier 3 (Unicode injection) then PRD v0.5
```

**Why Isaac**: AppleScript dialog interaction requires Logic Pro running + user input. Cannot be automated (visual confirmation required).

## Expected Outcome

- 1064 → 1074+ tests PASS
- `goto_marker { name: "VOCALS" }` live → reaches accurate sub-bar
- `logic://markers` response: `position_source` + `is_canonical` 100% included
- v3.1.11 NG10 closed
- Boomer P2-3 closed
- Version 3.2.0 (minor bump — new nav capability)
