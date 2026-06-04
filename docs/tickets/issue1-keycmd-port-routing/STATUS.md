# Pipeline Status: issue1-keycmd-port-routing

> Historical record (2026-06-05 docs refresh): latest production-readiness and live E2E evidence is in `README.md`, `CHANGELOG.md`, and `docs/live-verify-v3.4.5-rc5.md`; this file remains preserved implementation context.

**PRD**: docs/prd/PRD-issue1-keycmd-port-routing.md (v0.4 Approved + Phase 4 Loop 1/2 micro-revisions)
**Size**: L
**Current Phase**: 4 (Ticket review Loop 2 → entering Phase 5)
**Target Release**: v3.1.6 (v3.1.5 occupied by thomas-doesburg #3/#4/#5)
**GitHub Issue**: #1 (xaexx1)

## Ticket Status Definitions
- **Todo**: Not started
- **In Progress**: Implementation underway
- **In Review**: Review in progress
- **Done**: Complete (AC satisfied + tests PASS)
- **Invalidated**: Invalidated by a revert

## Tickets (dependency order)

| Ticket | Title | Status | Review | Notes |
|--------|-------|--------|--------|-------|
| T1 | HonestContract `.portUnavailable` enum + terminalErrorCodes | Todo | - | Foundation — T4/T6 depend on this |
| T2 | MIDIDispatcher `validatePort` + `validateMidiChannel` helpers | Todo | - | Foundation — T5 depends on this |
| T3 | NoteSequenceParser API change (`Result<[ParsedNote], NoteSequenceParseError>`) | Todo | - | Foundation — T5 / play_sequence / record_sequence depend on this |
| T4 | ChannelRouter `bypassReadinessOps` + available==false `.portUnavailable` branch | Todo | - | Depends: T1 |
| T5 | MIDIDispatcher port routing integration + 7 ops × 2 ports + record_sequence/mmc_* reject | Todo | - | Depends: T1, T2, T3 |
| T6 | MIDIKeyCommandsChannel `midi.send_*.keycmd` direct send path | Todo | - | Depends: T1, T4 |
| T7 | SystemDispatcher health detail (audited matrix + orphan ops) | Todo | - | Depends: None (independent) |
| T8 | Docs + Homebrew formula `xcode` removal + release.sh Issue #1 automation | Todo | - | Depends: T1-T7 (final integration step) |

## Review History

| Phase | Round | Verdict | P0 | P1 | P2 | P3 | Notes |
|-------|-------|---------|----|----|-----|-----|-------|
| 2     | 1     | HAS ISSUE | 0 | 4 | 5 | 0 | strategist+guardian+boomer consensus |
| 2     | 2     | HAS ISSUE | 0 | 4 | 4 | 2 | Loop 2 — KeyCmd readiness gate, matrix accuracy, record_sequence scope, NoteSequenceParser API |
| 2     | 3     | MIXED → micro-revision | 0 | 1 (matrix) | 4 | 1 | strategist ALL PASS, guardian HAS ISSUE, boomer ESCALATE — Rules §8 3-attempt limit → proceed after v0.4 micro-revision |
| 4     | 1     | HAS ISSUE | 0 | 9 | 11 | 6 | strategist HAS ISSUE / tester HAS ISSUE / guardian ALL PASS / boomer RECONSIDER — visibility defects + Live verification ownership gap + T6 missing deps, etc. |
| 4     | 2     | micro-revision applied | - | - | - | - | T2/T4 visibility AC-0 added, T6 deps T1+T3+T4, T2 empty port alignment, T2 EC tests 16-18 added, T4 invariant bidirectional+T5 dependency noted, T5 string-equality noted, T6 mock reuse+pitch_bend convention, T8 AC-12 Live verification gate, target v3.1.5→v3.1.6 |
| 6     | 1     |         |    |    |     |     |       |

## v0.4 Micro-revision Items (applied after Loop 3)

1. AC-3.4 matrix NavigateDispatcher factual correction (smart_controls/plugin_windows/automation handled separately, automation.toggle_view = logic_navigate exposed, automation.set_mode primary MCU)
2. AC-5.1 health detail orphan ops accuracy
3. §4.1 router-gate available==false → direct `.portUnavailable` HC envelope return noted explicitly
4. §4.1 readiness bypass rationale chicken-and-egg framing
5. AC-2.6 notes ch field BREAKING second table added
6. §8.1 test names + count corrected (8→7 ops, 16→14 cases, IgnoresWithWarning→RejectsPort)
7. §8.1 routingTable invariant test added (prevents parallel-list trap)
8. §4.1 diagram + §4.3 stale comment corrected
