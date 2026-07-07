# MIDI Region Drag Export Harness Evidence

Date: 2026-07-07

## Scope

This adds a guarded live harness for `PRD-midi-readback-vNext` T0. It does **not**
claim a State A selected-region read-back surface.

## Harness

- Script: `Scripts/spike-midi-region-drag-export.swift`
- Default behavior: refuses to post mouse events unless
  `LOGIC_PRO_MCP_ARM_REGION_DRAG=1` is set.
- Required armed arguments: `--source x,y`, `--destination x,y`, and explicit
  `--export-dir <path>`.
- Controlled file gate: snapshots `.mid` files in the export directory before drag,
  then reports only a newly modified positive-size `.mid`.

## Verified Dry Run

Command:

```bash
swift Scripts/spike-midi-region-drag-export.swift
```

Observed result:

```json
{"record_type":"region_drag_preflight","status":"blocked","note":"Refusing live drag until LOGIC_PRO_MCP_ARM_REGION_DRAG=1 is set; this prevents accidental timeline mutation."}
```

Exit code: `2` as expected for an unarmed hazardous operation.

## Live Logic Rerun

Command:

```bash
LOGIC_PRO_MCP_SPIKE_TIMEOUT=12 \
LOGIC_PRO_MCP_MIDI_EXPORT_DIR=/tmp/LogicProMCP-spike-20260707 \
LOGIC_PRO_MCP_MIDI_EXPORT_FILENAME=selection-20260707.mid \
LOGIC_PRO_MCP_BINARY=.build/release/LogicProMCP \
python3 Scripts/spike-midi-export.py
```

Observed result:

- Logic Pro 12.3 was running with a visible scratch document.
- The MCP server initialized and `logic://tracks` became readable.
- `record_sequence` did not create the sentinel track in this run because the
  MIDI import menu click failed before the file-open dialog appeared.
- Failure class: `System Events` Apple-event permission denied (`-1743`) from
  this harness launch context.
- Export menu enumeration also failed with the same permission denial, so no
  controlled `.mid` artifact was created.
- Cleanup observed no newly-created track from this run.

Verdict: **gate failed**. This rerun proves the current launch context cannot
drive the import/export menu path. It does not satisfy the controlled export +
`SMFReader` + sentinel-equality State A gate.

## Remaining Gate

Live Logic QA is still required before T3/T4 can start:

- scratch project only
- known sentinel MIDI region
- verified source/destination screen coordinates
- post-drag `.mid` parse via `SMFReader`
- sentinel equality
- in-Logic rollback verification if no controlled file appears
