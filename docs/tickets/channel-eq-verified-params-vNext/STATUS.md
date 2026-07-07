# Pipeline Status: Channel EQ Verified Params + rename_marker vNext

**PRD**: `docs/prd/PRD-channel-eq-verified-params-vNext.md`
**Status**: T0 factory-metadata census smoke verified; live insert verified; parameter activation still blocked
**Execution rule**: no registry activation and no marker rename implementation without live census/read-back evidence.

## Tickets

| Ticket | Title | Status | Gate |
|--------|-------|--------|------|
| T0 | AudioUnit parameter API census spike | Factory-only smoke verified | active-instance or explicit factory-only verdict |
| T1 | Preset/project-state census spike | Todo | parameter values mapped to track/insert identity |
| T2 | Automation/control-surface feedback spike | Todo | write/read-back evidence or reject |
| T3 | Channel EQ registry activation | Blocked | T0/T1/T2 PASS |
| T4 | `rename_marker` live gate | Todo | marker write/read-back/rollback |

## Dependency Graph

```text
T0 ┐
T1 ├─> T3
T2 ┘

T4 independent, shares live scratch session
```

## Evidence Gate

Channel EQ State A requires census artifact + duplicate/scratch write/read-back. `rename_marker` State A requires marker identity + editable text path + post-write read-back + rollback.

## Current Evidence

- `Scripts/spike-channel-eq-au-census.swift` enumerates Apple `AUNBandEQ` factory metadata through public AudioUnit APIs.
- Smoke run verified on 2026-07-07: emitted parameter records with `status:"factory_metadata_only"` and `activation_evidence:false`.
- Live rerun on 2026-07-07: `logic_tracks.create_audio` and `logic_plugins.insert_verified` proved Channel EQ insert State A on a scratch track, but the parameter editor census did not produce active hosted-insert parameter values/read-back. The run failed at the editor-opening / System Events harness boundary and cleanup track deletion also failed in that context.
- No active Logic hosted insert write/read-back evidence has been captured, so T3 registry activation remains blocked.

## Verification

- `swift test --no-parallel` after implementation tickets.
- Live Logic 12.3 E2E evidence for any activated surface.
- Review gate checks no inferred registry entries.
- **TDD**: red tests written and FAIL-verified before implementation; no dead-`#expect` forms (repo footgun #92).
- **Cumulative review (CTO)**: each ticket completion reviews T(n-1)+T(n) diff together + full suite; a full cumulative review runs before T3 (registry activation) and before any T4 production change.
- **Spike safety**: all spikes run on scratch/duplicate projects only; census/spike scripts must never write user presets, user projects, or shared AU state.
