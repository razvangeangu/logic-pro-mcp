# Pipeline Status: MIDI Read-Back vNext

**PRD**: `docs/prd/PRD-midi-readback-vNext.md`
**Status**: Gate harness added; live State-A proof failed in current launch context
**Execution rule**: no implementation ticket may start until one evidence gate proves a controlled selected-region read-back path.

## Tickets

| Ticket | Title | Status | Gate |
|--------|-------|--------|------|
| T0 | Region drag-to-Finder export spike | Harness dry-run verified | Live controlled export evidence |
| T1 | Logic project/package event-reader spike | Todo | Saved scratch project note equality |
| T2 | Operator-assisted export contract | Todo | Explicit non-default profile decision + exact-path proof |
| T3 | `logic_midi.read_selection_notes` implementation | Blocked | T0 or T1 or T2 PASS |
| T4 | `record_sequence verify_notes` integration | Blocked | T3 PASS |

## Dependency Graph

```text
T0 ┐
T1 ├─> T3 -> T4
T2 ┘
```

## Evidence Gate

State A requires:

- registered controlled `.mid` path
- newly created file with positive size and fresh mtime
- `SMFReader.parse` success
- sentinel/requested notes equality
- selected-region or created-region identity captured
- no leftover Logic modal/menu

## Current Evidence

- `Scripts/spike-midi-region-drag-export.swift` refuses hazardous live mouse drag unless `LOGIC_PRO_MCP_ARM_REGION_DRAG=1` is set.
- Dry run verified on 2026-07-07: unarmed execution emits `record_type:"region_drag_preflight"`, `status:"blocked"` and exits `2`.
- Live rerun on 2026-07-07: `Scripts/spike-midi-export.py` initialized the MCP server and read `logic://tracks`, but `record_sequence` failed before sentinel import because this harness launch context cannot send Apple events to `System Events` (`-1743`). Export menu enumeration failed for the same reason, so no controlled `.mid` artifact was created.
- No live controlled `.mid` export evidence has been captured yet, so T3/T4 remain blocked.

## Verification

- Unit: Red tests named in each ticket; FAIL-verified before implementation; no dead-`#expect` forms (repo footgun #92).
- Integration: scratch-project spike scripts.
- Manual QA: live Logic 12.3 happy path plus deliberate failure path.
- Review: **cumulative review on every ticket completion (T(n-1)+T(n) diff + full `swift test --no-parallel`)**; full cumulative review before T3; final QA review before public docs/API claim.
- Safety: all spikes scratch-project-only; T0 drag additionally requires in-Logic rollback assertion (ticket AC) — never a user project.
