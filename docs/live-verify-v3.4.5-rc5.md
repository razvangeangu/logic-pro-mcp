# Live Verification Runbook — v3.4.5-rc5

Historical prerelease record. Latest stable release and issue #10-#13 evidence: `docs/live-verify-v3.4.6.md`, `docs/releases/v3.4.6.md`, and `docs/tickets/mixer-verification/VERIFICATION-2026-06-09.md`.

Date: 2026-06-05 KST
Scope: current main hardening, release binary, live Logic Pro 12.2 session, and final MIDI-only v4 composition artifact.

## Tier 1 — Local Build And Tests

| Gate | Result |
|---|---:|
| `swift test` | PASS, `1143 / 1143` |
| `swift build -c release` | PASS |
| `python3 -m py_compile artifacts/acid-track-composition-v4/import_v4_sequential.py` with `PYTHONPYCACHEPREFIX` | PASS |

## Tier 2 — Live Logic Pro 12.2 E2E

| Check | Result |
|---|---:|
| Release binary launch | PASS, `.build/release/LogicProMCP` |
| Graceful shutdown | PASS, Ctrl-C / SIGINT stopped channels cleanly |
| Logic Pro session | PASS, Logic Pro 12.2 visible |
| Channel health | PASS, all 7 channels ready |
| Permissions | PASS, Accessibility and Automation granted |
| `logic_transport set_tempo` | PASS, requested/observed `127 BPM`, `verified:true` |
| `logic_project save_as` | PASS, `verified:true`, observed package mtime `2026-06-04T14:38:48Z` |
| `logic://project/info` semantics | PASS, live transport tempo/sample-rate can promote; visible AX rows are not promoted to whole-project `trackCount` |

## Tier 3 — v4 Composition Artifact

Final package:

```text
artifacts/acid-track-composition-v4/acid-track-composed-midi-v4.logicx
```

Expected MIDI region names found in saved `ProjectData`:

- `v4_909_kick`
- `v4_909_clap_snare`
- `v4_909_hats`
- `v4_house_percussion`
- `v4_acid_main_303`
- `v4_acid_answer_303`
- `v4_sub_pump`
- `v4_rave_chord_stabs`
- `v4_metallic_lead`
- `v4_vocal_like_synth`
- `v4_noise_transitions`

Artifact constraints:

- MIDI/software-instrument composition only.
- No reference recording imported.
- No separated stems imported.
- No packaged audio files required or expected.
- Sequential import runner waits for `verified:true` after each `logic_midi.import_file` call.

## Current Honest Limits

- AX viewport reads can report fewer visible tracks than the saved package contains. For artifact completion, package-level `ProjectData` verification is authoritative.
- `project/info.trackCount` is metadata, not a visible-row counter. Use `logic://tracks` for live visible rows and `logic://project/info` for provenance-tagged project metadata.
- Public install docs now point at stable `v3.4.6`; this rc5 runbook remains historical prerelease evidence.
