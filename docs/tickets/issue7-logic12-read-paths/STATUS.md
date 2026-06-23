# Pipeline Status: Issue #7 Logic 12.x Read-Path Recovery

> Historical record. Current stable evidence is in `README.md`, `CHANGELOG.md`, and `docs/live-verify-v3.7.0.md`; previous stable evidence remains in `docs/live-verify-v3.6.0.md`; this file remains preserved implementation context.

**PRD**: docs/prd/PRD-issue7-logic12-read-paths.md (v0.2 Approved)
**Size**: L
**Current Phase**: 3 (Tickets generated; Phase 4 review next)
**Started**: 2026-05-06
**Owner**: Claude (autonomous, on Isaac's behalf)

## Tickets

| Ticket | Title | Status | Review | Notes |
|--------|-------|--------|--------|-------|
| T1 | LogicProjectFileReader (plist parser, path hardening) | Todo | - | Foundation |
| T2 | AppleScriptChannel.currentDocumentPath static helper | Todo | - | Depends: none |
| T3 | wrapWithCacheEnvelope `extras` parameter + migration | Todo | - | Depends: none |
| T4 | ResourceHandlers tier-merge for project_info | Todo | - | Depends: T1, T2, T3 |
| T5 | ResourceHandlers tier-merge for tracks + placeholders | Todo | - | Depends: T1, T2, T3 |
| T6 | AX hardening: tracks (strict getTrackHeaders) + markers (AXRole) + delete AppleScript-primary | Todo | - | Depends: none |
| T7 | Issue7IntegrationTests | Todo | - | Depends: T4, T5, T6 |
| T8 | BackwardCompat regression + Logic version detect cleanup | Todo | - | Depends: T4, T5 |

## Review History

| Phase | Round | Verdict | P0 | P1 | P2 | Notes |
|-------|-------|---------|----|----|----|-------|
| 2     | 1     | REQUEST CHANGES | 2 | 5 | several | strategist + guardian + boomer; PRD v0.2 incorporates all P0/P1 |
| 2     | 2     | ALL PASS (PRD v0.2) | 0 | 0 | ≤2 | Boomer P0 (G5 cache poisoning) addressed by tier-merge layer shift |
| 4     |       |                 |    |    |     |       |
| 6     |       |                 |    |    |     |       |
