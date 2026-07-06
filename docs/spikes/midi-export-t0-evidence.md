# T0 Live Spike Evidence — MIDI Export Read Path (WS5)

**Date**: 2026-07-07
**Verdict**: **GATE FAILED → T5b honest-deferred** (T5a ships independently)
**Environment**: Logic Pro 12.x (build reporting server 3.8.0 baseline), macOS Retina 1920×1080 logical, English menu locale, Korean system locale.

## What the spike proved WORKS (reusable evidence)

1. **Menu navigation to the export command works via AXPress.** Ground-truth captured (English UI):
   - `File` = menu bar item 3 of menu bar 1.
   - `File > Export` submenu children (exact order): `Region/Cell to Loop Library…`, `Regions as Audio Files…`, `Audio Files As…`, (sep), `Selection as Audio File…`, **`Selection as MIDI File…`** (index 6), (sep), `Tracks as Audio Files…`, `All Tracks as Audio Files…`, `All MIDI Tracks as MIDI File…`, (sep), `Project as AAF File…`, `Project to Final Cut Pro XML…`, `Project as Spatial Audio…`, `Score as MusicXML…`.
   - Matching rule that works: descend only into the parent titled exactly `Export`; click the child containing `Selection as MIDI`. (An earlier fuzzy `contains "MIDI"` rule wrongly clicked `Open Recent > "Project 3 — midi"`, a recent-file whose name contained "midi" — fixed to an exact substring + Export-parent guard.)
2. **`record_sequence` sentinel + region enumeration work.** A 3-note sentinel (C4/E4/G4, bars 1–4) imports as a verified MIDI region; `logic_project.get_regions` returns it with track/bar identity.
3. **Selection hypothesis holds structurally.** The imported region appears to remain the active selection (no explicit region-select op exists in the public surface; documented as a gap).

## The wall (why the live State-A path is deferred)

Logic's **"Save MIDI File as:" panel is an out-of-process NSSavePanel remote view** hosted by the Logic process (window subrole `AXDialog`, frame = full arrange window). It is **not drivable in this automation context**:

- **Inner controls are AX-opaque.** Enumerating the dialog (`entire contents`, recursive UI-element walk) yields children with empty `role`/`title` — the filename field, `Save`/`Cancel` buttons, and sidebar belong to the remote view service and expose no actionable AX elements to the host process. `AXPress`/`AXCancel` on the dialog return `missing value` / no-op.
- **Synthetic keyboard input is not delivered to the panel.** `Escape`/`Return`/typed path were verified NOT to reach it via three independent channels — `osascript keystroke`, `cliclick kp/t`, and cliclick after a focus-click — while the dialog stayed open every time. `IsSecureEventInputEnabled` confirmed **False**, so this is not a secure-input block; it is remote-view keyboard-routing (the arrange window retains key focus).
- **Mouse HID reaches the screen but is insufficient.** `cliclick` mouse-move/click post real HID events (verified), but a Save-As flow requires typing a controlled directory + filename, which needs keyboard — unavailable. Clicking `Save` with defaults would write `Untitled 54.mid` to an uncontrolled location (Macintosh HD root), failing the controlled-directory + sentinel-comparison contract (PRD AC-5.1/5.3).
- **Failure mode observed:** repeated automation attempts left Logic in a stuck modal stack (File menu tracking + save panel + "Go to folder" overlay), blocking the main event loop (UI frozen ~3 min; AX thread still answered). Recovery required force-terminating Logic. **Operational lesson: never leave a menu open across steps — an open menu's modal tracking loop swallows all subsequent synthetic clicks/keys and can wedge the app.**

## Classification

This is the same class of Logic live-UI wall the project has repeatedly honest-deferred (NG10 sub-bar nav; Logic 12.2 dialog 4-segment `AXSlider`; `.logikcs` programmatic install). The **T0 gate exists precisely to catch this before building the dependent surface** — it did.

## Decision (CTO)

- **Ship T5a** (`SMFReader` + `ExportTemporaryFiles`): environment-independent, fully unit-tested (39 tests), the reusable core value. The parser is correct and covered against the writer's own output plus the fixture matrix (running status, velocity-0 note-off, overlap, SMPTE rejection, VLQ/length bounds, format-1 tempo merge, 1-based channel).
- **Defer T5b** (`logic_midi.read_selection_notes` live State-A + `record_sequence verify_notes`): blocked on a keyboard-routable / AX-actionable export save panel, or a non-panel export trigger (e.g. region drag-export), neither available here. Revisit if a future Logic build exposes the save panel controls, or if an operator-driven interactive path is acceptable (the menu + parser halves are ready).

## Follow-up candidates (not this PR)

- Region drag-to-Finder export automation (mouse-only, bypasses save panel) — high fragility, separate spike.
- A public `region.select` op (gap found here) would strengthen any future export-by-identity flow.
- `cliclick`/HID keyboard routing into out-of-process save panels — investigate `LOGIC_PRO_MCP_CLICLICK` trust path + a dedicated panel-focus step.
