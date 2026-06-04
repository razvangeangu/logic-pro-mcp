# PRD: Issue #1 — MIDIKeyCommands port routing + channel encoding + setup honesty

> Historical record (2026-06-05 docs refresh): latest production-readiness and live E2E evidence is in `README.md`, `CHANGELOG.md`, and `docs/live-verify-v3.4.5-rc5.md`; this file remains preserved implementation context.

**Version**: 0.4
**Author**: Isaac (orchestrated via Claude Opus 4.7)
**Date**: 2026-05-04
**Status**: Approved (Loop 3 opinion divergence — strategist ALL PASS, guardian/boomer P1 residuals; Rules §8 3-iteration limit → micro-revision v0.4 → Phase 3 entry; v0.4 resolves all 4 P1 items via factual corrections)
**Size**: L
**GitHub Issue**: https://github.com/MongLong0214/logic-pro-mcp/issues/1
**Reporter**: xaexx1
**Target Release**: v3.1.6 (v3.1.5 occupied by Issue #3/#4/#5 thomas-doesburg AppleScript read-path resilience. Issue #1's BREAKING channel encoding change warrants a dedicated release for communication clarity — Phase 4 Loop 1 decision)
**Workflow**: C (Level 2 synchronous approval — contains BREAKING change)

**Revision history**:
- v0.1 (2026-05-04 initial draft): Phase 2 Loop 1 review found P1×4, P2×5 (HAS ISSUE)
- v0.2 (2026-05-04 revision): routing design replaced with dispatcher-level direct, scope expanded (play_sequence/record_sequence/pitch_bend/aftertouch), "all covered" → audited matrix, ScripterChannel excluded, Scripts/install.sh included. Loop 2 review found P1×4 (KeyCmd readiness gate / matrix accuracy / record_sequence position / NoteSequenceParser API)
- v0.3 (2026-05-04 revision): KeyCmd readiness bypass policy (router-level allowlist), AC-3.4 matrix factual correction (transport.play/stop rows removed, view rows unified, note.up_*/down_* orphan handling), record_sequence scope separation (NG7), NoteSequenceParser API change documented, validateMidiChannel float reject pattern, NG8 (mmc_*/sysex/step_input port unsupported). Loop 3 review: strategist ALL PASS w/ P3 cosmetic, guardian HAS ISSUE w/ P1 matrix accuracy, boomer ESCALATE w/ P1×4. Rules §8 (3-iteration limit) prohibits additional loops — proceeding with micro-revision.
- v0.4 (2026-05-04 micro-revision): AC-3.4 matrix NavigateDispatcher factual correction (smart_controls/plugin_windows as orphan, automation.toggle_view=logic_navigate exposed explicitly, automation.set_mode primary MCU corrected, capture_recording cgEvent unmapped noted), §4.3 record_sequence style comment corrected, §8.1 test name + count corrected (8→7 ops, 16→14 cases, IgnoresWithWarning→RejectsPort), AC-2.6 notes ch field BREAKING table added (Boomer P1-3), §4.1 router-gate available==false branch now explicitly returns portUnavailable HC envelope directly (Boomer P1-2), AC-5.1 automation.toggle_view "always-required" removed (cgEvent fallback exists), §4.1 readiness rationale chicken-and-egg framing.

---

## 1. Problem Statement

### 1.1 Background
A v3.1.1 user (`xaexx1`) filed GitHub Issue #1 with an accurate P1-level diagnosis: the `MIDIKeyCommands` channel does not work in Logic Pro 12.2 + macOS 26.5. Releases v3.1.2–v3.1.4 addressed HC envelope wrapping, live race fixes, and AX occlusion, but the root cause — **port routing itself and misleading docs** — remained untouched.

The reporter performed precise core analysis:
- Logic 12.2 Key Commands panel rejects `.plist` import (only accepts `.logikcs` schema)
- `logic_midi.send_cc` sends exclusively to the `LogicProMCP-MIDI-Internal` port → when the user attempts manual binding via Logic Controller Assignments → Learn Mode, the actual send port of the `MIDIKeyCommands` channel (`LogicProMCP-KeyCmd-Internal`) does not match → binding capture fails
- `channel: 16` input results in Logic capturing Ch 1 (code analysis: `midiChannel(0...16)` allowed + wire mask `0x0F` → `16 & 0x0F = 0` → off-by-one)
- Homebrew formula `depends_on xcode: ["15.0", :build]` blocks CLT-only hosts (reporter worked around with manual binary install)

### 1.2 Problem Definition (v0.2 expanded)

1. **Port routing defect**: `logic_midi.send_*` **6 ops** (send_cc / send_note / send_chord / send_program_change / send_pitch_bend / send_aftertouch) + `play_sequence` + `record_sequence` all route exclusively to the `MIDI-Internal` port → the MIDIKeyCommands channel's manual MIDI Learn workflow cannot be made scriptable.
2. **Channel encoding defect**:
   - **(a)** `send_cc` / `send_note` / `send_chord` / `send_program_change`: allows `0...16` + direct `0x0F` masking → `channel=16` → wire 0 (Ch 1). Off-by-one.
   - **(b)** `send_pitch_bend` / `send_aftertouch`: no channel validation at all (`params["channel"].flatMap(UInt8.init) ?? 0` raw cast — `CoreMIDIChannel.swift:201,212`). `channel: 17` input causes UInt8 truncation + engine `& 0x0F` → silent corruption. A larger problem than (a).
   - **(c)** The `ch` field in the `notes` string format `pitch,offsetMs,durMs[,vel[,ch]]` for `play_sequence` / `record_sequence` is annotated as `UInt8 // 0..15` in `NoteSequenceParser.swift:14`. Inconsistent with the other 6 ops from the user's perspective.
3. **Misleading docs**: `docs/SETUP.md §4` presents the `.plist` Import path as primary guidance, which does not work in Logic 12.2. `Scripts/install.sh:235` is identical. `Scripts/install-keycmds.sh` + `Scripts/keycmd-preset.plist` header comments are the same. Users spend 25+ minutes troubleshooting before filing a GitHub issue.
4. **Homebrew install blocked**: `depends_on xcode` blocks `brew install` on CLT-only hosts. Since release is an ADHOC pre-built binary download, no build-time Xcode dependency exists.
5. **MIDIKeyCommands channel partial redundancy**: Audit of `MIDIKeyCommandsChannel.swift:34-108` `mappingTable`:
   - **Covered by other dispatchers**: transport/edit/project/navigate family (Undo/Redo/Cut/Copy/Paste/Save/Quantize/Split/Play/Stop/Record/Goto, etc.)
   - **Partially covered**: track family via `logic_tracks` (missed citation in PRD v0.1), automation family via `logic_tracks.set_automation`
   - **No other path (channel-only)**: `note.up_semitone` / `note.up_octave` / `note.down_semitone` / `note.down_octave` (4 ops) — not exposed in any other dispatcher case, no CGEvent mapping
   - **Only partially covered elsewhere**: `view.toggle_*` family — only some exposed via dispatcher
   - Therefore, "All covered" is inaccurate — replace with audited matrix.

### 1.3 Impact of Not Solving
- New users follow SETUP.md, encounter greyed-out `.plist` file in Logic 12.2 → 25+ minutes lost → abandon or work around with manual binary install (reporter's case)
- Automation scripts sending `channel:16` actually transmit on Ch 1 → silent wrong-channel routing → difficult to debug
- Invalid input like `pitch_bend channel: 100` causes silent UInt8 truncation → even deeper wrong-channel
- Health report claiming "MIDIKeyCommands channel ready" is false → AI agents trust the channel and proceed → nothing actually works
- Users blocked if docs incorrectly guide them to use `logic_edit` for channel-only ops like `note.up_octave`
- Homebrew users blocked from install → adoption deterred

## 2. Goals & Non-Goals

### 2.1 Goals (v0.3 reordered)
- [ ] **G1**: Add `port` parameter (`"midi"|"keycmd"`, default `"midi"` for backward compat) to `logic_midi.send_*` 6 ops + `play_sequence`. 7 ops × 2 ports = 14 routingTable entries. **`record_sequence` does not support `port`** (NG7 — SMF import path has no meaning for the KeyCmd port). Enables scriptable manual MIDI Learn workflow.
- [ ] **G2**: Unify all MIDI channel input semantics to 1-based (1..16, music convention). Return `invalid_params` for 0/17+/non-integer input. Wire byte = `(channel - 1) & 0x0F`. Scope: send_* 6 ops + play_sequence + record_sequence (`NoteSequenceParser` API type change — `Result<[ParsedNote], NoteSequenceParseError>`).
- [ ] **G_NEW (v0.3)**: Introduce a router-level bypass allowlist so ChannelRouter's readiness gate passes `midi.*.keycmd` operations even for `manual_validation_required` channels. MIDI transmission to the KeyCmd port is possible even before user approval (manual MIDI Learn seeding is the key use case at the pre-approval stage).
- [ ] **G3**: Rewrite `SETUP.md` / `TROUBLESHOOTING.md` / `Scripts/install.sh` / `Scripts/install-keycmds.sh` / `Scripts/keycmd-preset.plist` header. Remove Import path, add 2+ manual MIDI Learn examples + explicit time estimates + audited coverage matrix.
- [ ] **G4**: Remove `depends_on xcode` from Homebrew formula (ADHOC binary has no build dependency). Add comment to `Formula/logic-pro-mcp.rb` clarifying ADHOC-only path.
- [ ] **G5**: Honest MIDIKeyCommands channel health detail message — "Manual MIDI Learn required + audited coverage matrix link + channel-only ops explicitly listed (note.up_*/down_*)".
- [ ] **G6**: Guarantee backward compatibility — existing calls without `port` behave identically to before + same error message wording preserved. Channel encoding change is an explicit BREAKING change documented in CHANGELOG + Issue #1 auto-comment + GitHub Release notes as BEFORE/AFTER tables.
- [ ] **G7**: Automate Issue #1 closure — add `gh issue comment 1` + `gh issue close 1` steps to `Scripts/release.sh` (or close link in release notes).

### 2.2 Non-Goals
- **NG1**: `--install-keycmds` Swift CLI subcommand (reporter option 1) — reverse-engineering `.logikcs` schema + direct `MROF` chunk injection is large scope and risks direct modification of Logic preferences. Separate to v3.2 PRD.
- **NG2**: Full removal of MIDIKeyCommands channel — maintain backward compat. External users who have completed manual binding must continue to work. Only document redundancy + channel-only ops honestly in health.
- **NG3**: Automate Manual MIDI Learn UI (operate Controller Assignments panel via AppleScript/AX) — Logic's Controller Assignments has limited AX exposure; practical automation is not feasible. Separate R&D area.
- **NG4**: Evaluate redundancy of other channels (Scripter, MCU) — out of scope for this PRD.
- **NG5 (v0.2 new)**: `port: "scripter"` option not included. ScripterChannel is exclusively for `plugin.set_param`/`mixer.set_plugin_param` (`ScripterChannel.swift:46-48` execute guard); it has no responsibility to handle `midi.send_*`. v3.1.5 supports only two values: `port: "midi" | "keycmd"`. If Scripter port routing is needed, a separate PRD must cover ScripterChannel transport extension + JSFX recording policy.
- **NG6 (v0.2 new)**: Adding new dispatcher entries for **orphan ops** registered in mappingTable but not exposed in any dispatcher case (`note.up_*` / `note.down_*`, etc.) — tracked as a separate follow-up issue. v3.1.5 docs will only honestly state: "orphan — not reachable from any logic_* tool today; manual MIDI Learn binding is the only call path."
- **NG7 (v0.3 new)**: `record_sequence` does not support `port` parameter. `record_sequence` is an SMF import path (owned by TrackDispatcher) and is unrelated to virtual MIDI port transmission. Providing a `port` parameter will be rejected at dispatcher-level enum validation (silent ignore removed — reverses v0.2 E14 decision).
- **NG8 (v0.3 new)**: `mmc_play` / `mmc_stop` / `mmc_record` / `mmc_locate` / `send_sysex` / `step_input` / `create_virtual_port` do not support `port`. Input will be rejected at dispatcher-level enum validation. `mmc_*` is SysEx broadcast targeting all listening devices — KeyCmd port has no meaning. `send_sysex`/`step_input`/`create_virtual_port` also have separate responsibilities.

## 3. User Stories & Acceptance Criteria

### US-1: Scriptable manual MIDI Learn flow
**As an** AI agent operator, **I want** `logic_midi.send_cc` to allow selecting which virtual MIDI port to transmit to, **so that** I can use an automation script to seed MIDIKeyCommands bindings via Logic's Controller Assignments → Learn Mode.

**Acceptance Criteria:**
- [ ] **AC-1.1**: Calling `logic_midi.send_cc {controller: 6, value: 127, channel: 16, port: "keycmd"}` sends the message to the `LogicProMCP-KeyCmd-Internal` virtual port. Verification: (a) unit test — confirm KeyCmd transport handle invocation (verify `MIDIKeyCommandsChannel.transport.send` called), (b) live — with Logic 12.2 Controller Assignments → Learn Mode active, transmit with `port:"keycmd"` → confirm `LogicProMCP-KeyCmd-Internal` captured as input (both reporter's environment and Isaac's environment).
- [ ] **AC-1.2**: Without `port` specified, existing routing is 100% preserved — transmits to `MIDI-Internal` port + identical error message wording (validated via string-equality regression test).
- [ ] **AC-1.3**: Invalid `port` value (`"foo"` / `"scripter"` / `""`, etc.) causes **dispatcher-level enum validation** → State C `invalid_params` + hint `"port must be one of: midi, keycmd"`. Does not reach the channel.
- [ ] **AC-1.4**: `send_note` / `send_chord` / `send_program_change` / `send_pitch_bend` / `send_aftertouch` / `play_sequence` all support the same `port` parameter. Consistent routing (**7 entry points — record_sequence excluded in v0.3**, see NG7).
- [ ] **AC-1.5**: Tool description (manifest.json + `MIDIDispatcher.description`) includes exact wording: `"port: virtual MIDI source selection (\"midi\" default | \"keycmd\" — for manual MIDI Learn seeding); channel: MIDI channel number 1..16 (1-based) — independent from port"`. The `ch` field inside play_sequence's `notes` string is documented as separate from the entry-level `port` parameter.
- [ ] **AC-1.6 (v0.3 new)**: For ops that do not support `port` (record_sequence / mmc_* / send_sysex / step_input / create_virtual_port), providing `port` input causes dispatcher-level validation to return State C `invalid_params` + hint `"port parameter not supported for <op_name>"`. Silent ignore is prohibited.
- [ ] **AC-1.7 (v0.3 new)**: Introduce `midi.*.keycmd` operation key bypass allowlist in ChannelRouter's readiness gate. When `MIDIKeyCommandsChannel.healthCheck()` returns `available: true, ready: false` (manual_validation_required), `midi.*.keycmd` operations still reach execute. When `available: false` (virtual port not created), operations are still blocked + State C `port_unavailable` returned.

### US-2: Honest 1-based MIDI channel encoding (BREAKING)
**As a** caller, **I want** `channel: 16` to actually transmit on MIDI Channel 16, **so that** Logic's channel display matches the input semantics.

**Acceptance Criteria:**
- [ ] **AC-2.1**: `channel: 16` input results in the wire status byte's lower nibble = `0xF` (Logic displays Ch 16). Applies to: send_cc / send_note / send_chord / send_program_change / send_pitch_bend / send_aftertouch + play_sequence/record_sequence parser.
- [ ] **AC-2.2**: `channel: 1` input results in wire lower nibble = `0x0` (Logic displays Ch 1).
- [ ] **AC-2.3**: `channel: 0` or `channel: 17+` input returns State C `invalid_params` + hint: `"channel must be 1..16 (1-based)"`.
- [ ] **AC-2.4**: Non-integer channel (`channel: 1.5`) input is rejected by strict integer parser → `invalid_params` + hint: `"channel must be integer 1..16"`. Current `intParam` with JSON `1.5` (`Value.double` case) yields `intValue == nil` + `stringValue == nil` → silent default fall-through. **v3.1.5 fix**: a new helper `validateMidiChannel(_:)` in `MIDIDispatcher` case-switches on raw `Value` type — only `.int(let n)` passes; `.double(let f)` attempts `Int(exactly: f)` and passes if round-trip matches (e.g., 1.0 OK, 1.5 rejected); `.string(let s)` attempts `Int(s)`. All paths validate the 1..16 range.
- [ ] **AC-2.5**: pitch_bend / aftertouch currently have no validation → apply the new `midiChannel(_:)` validation function consistently + standardize State C envelope.
- [ ] **AC-2.6 (v0.4 expanded)**: BREAKING change communication steps:
  - CHANGELOG **Table #1 — top-level `channel:` parameter** (send_* 6 ops + play_sequence):
    ```
    | input        | v3.1.4 wire    | v3.1.5 wire | Logic display |
    |--------------|----------------|-------------|---------------|
    | channel:1    | 0x?0 (ch1)     | 0x?0 (ch1)  | Ch 1 (unchanged) |
    | channel:16   | 0x?0 (ch1)     | 0x?F (ch16) | Ch 16 (CHANGED — was Ch 1) |
    | channel:0    | 0x?0 (ch1)     | error       | invalid_params |
    | channel:17   | 0x?1 (truncate)| error       | invalid_params |
    | channel:1.5  | 0x?0 (default) | error       | invalid_params (strict integer) |
    ```
  - CHANGELOG **Table #2 — `notes` substring `ch` field** (play_sequence + record_sequence parser, Loop 3 Boomer P1-3):
    ```
    | input fragment        | v3.1.4 behavior        | v3.1.5 behavior |
    |-----------------------|------------------------|-----------------|
    | "60,0,500,127,0"      | wire ch1 (0 → wire 0)  | parse error (ch=0 invalid in 1-based) — whole parse fails |
    | "60,0,500,127,1"      | wire ch2 (1 → wire 1)  | wire ch1 (1-based: ch1 → wire 0) — CHANGED |
    | "60,0,500,127,15"     | wire ch16 (15 → wire 0xF) | wire ch15 (1-based: ch15 → wire 0xE) — CHANGED |
    | "60,0,500,127,16"     | invalid (out of 0..15) → silent default | wire ch16 (1-based: ch16 → wire 0xF) — NEW VALID |
    | "60,0,500,127" (omit) | wire ch1 (default 0)   | wire ch1 (default 1-based ch1) — unchanged |
    | "60,0,500,127,17"     | invalid → silent default | parse error — whole parse fails |
    ```
    Migration: if user automation scripts use the `ch` field inside `notes` as a 0-based wire value, increment by 1. ch=0 is invalid (use `ch=1` to mean Ch 1). Also, NoteSequenceParser changes from partial-parse silent fall-through to strict whole-parse-fail — a single invalid segment fails the entire call (`Result<[ParsedNote], NoteSequenceParseError>`).
  - GitHub Release notes: prominent `### ⚠️ BREAKING` section + both tables included
  - Issue #1 auto-comment + close (add step to release.sh)
  - Tool description (`MIDIDispatcher.description` + `TrackDispatcher.description`) inline "channel: 1..16 (1-based)". play_sequence/record_sequence additionally note "`notes` ch field also 1-based since v3.1.5".

### US-3: Honest documentation for Logic 12.2
**As a** new user, **I want** SETUP.md to match the actual behavior of Logic 12.2, **so that** I can proceed step by step without 25+ minutes of trial and error.

**Acceptance Criteria:**
- [ ] **AC-3.1**: All `.plist` Import guidance in `docs/SETUP.md` is completely removed (the relevant section, all MIDIKeyCommands-related mentions).
- [ ] **AC-3.2**: A step-by-step Manual MIDI Learn guide is written with **at least 2 example** bindings (showing the repeating pattern — e.g., `Edit > Undo` once, `Track > New Audio Track` once). Each step includes the Logic UI click location + MCP call command (with `port:"keycmd"`) + screenshot or detailed description. All steps covered: entering/exiting the Learn panel cycle + Save Assignments.
- [ ] **AC-3.3**: Time estimate explicitly stated (e.g., "Minimum binding: ~2 min (1 binding), Recommended full binding: ~25 min (48 bindings) — minimal path covering channel-only ops recommended ~5 min").
- [ ] **AC-3.4 (v0.3 corrected)**: **Audited coverage matrix** — only rows verified against the actual `MIDIKeyCommandsChannel.swift:34-110` mappingTable. "All covered" phrasing prohibited. 4-column matrix:
  ```
  | mappingTable op (CC#)        | dispatcher entry exposing it    | router primary fallback     | requires keycmd binding? |
  |------------------------------|---------------------------------|-----------------------------|--------------------------|
  | edit.undo (30) / redo (31)   | logic_edit.undo / .redo         | accessibility, applescript  | NO — optional            |
  | edit.cut/copy/paste/select_all | logic_edit                    | accessibility, cgevent      | NO — optional            |
  | edit.quantize/join/duplicate/split/normalize/delete/bounce_in_place | logic_edit | accessibility, cgevent | NO — optional |
  | edit.toggle_step_input       | logic_edit.toggle_step_input    | midiKeyCommands, cgevent    | RECOMMENDED              |
  | project.save / save_as / bounce | logic_project                | applescript                 | NO — optional            |
  | transport.toggle_cycle (72)  | logic_transport.toggle_cycle    | midiKeyCommands, accessibility | RECOMMENDED          |
  | transport.capture_recording (73) | (no other dispatcher entry) | midiKeyCommands only        | YES                      |
  | transport.toggle_metronome / toggle_count_in (98/99) | logic_transport | midiKeyCommands, accessibility | RECOMMENDED         |
  | track.create_audio / create_instrument / create_external_midi / duplicate / delete / create_stack / create_drummer | logic_tracks | midiKeyCommands, cgevent | RECOMMENDED |
  | view.toggle_mixer/piano_roll/library/inspector/score_editor/step_editor (50-51, 55-56, 59, 48) | logic_navigate.toggle_view | midiKeyCommands, cgevent | RECOMMENDED |
  | nav.goto_marker / create_marker / delete_marker / zoom_to_fit / set_zoom_level | logic_navigate | midiKeyCommands, cgevent | RECOMMENDED |
  | automation.set_mode (84)     | logic_tracks.set_automation     | mcu (primary), midiKeyCommands, cgevent | RECOMMENDED  |
  | automation.toggle_view (85)  | logic_navigate.toggle_view {automation} | midiKeyCommands, cgevent (`.key(0)`) | RECOMMENDED  |
  ```
  **Orphan ops separate section** (registered in mappingTable + routingTable but not exposed in any dispatcher case — Loop 3 boomer P1-4 verification additions):
  - `note.up_semitone (90)` / `note.down_semitone (91)` / `note.up_octave (92)` / `note.down_octave (93)` — manual MIDI Learn binding possible but no logic_* tool has a call path.
  - `view.toggle_smart_controls (54)` / `view.toggle_plugin_windows (58)` / `view.toggle_automation (57, distinct — different from automation.toggle_view (85))` — `NavigateDispatcher.swift:112-128` switch routes only 7 view-keys: `mixer / piano_roll / score / step_editor / library / inspector / automation`. `smart_controls`/`plugin_windows` have no dispatcher exposure. `view.toggle_automation` (CC 57) is in mappingTable but the dispatcher's `automation` view-key maps to `automation.toggle_view` (CC 85) — a separate op.
  - `transport.capture_recording (73)` — not mapped in cgEvent (`CGEventChannel.swift:115` absent). routingTable lists `[.midiKeyCommands, .cgEvent]` but cgEvent has no mapping → effectively keycmd-only.
  - **AC decision (v0.4)**: Orphan ops → register follow-up issue (NG6) for dispatcher entry additions + document in docs as "manual binding possible but no automatic call path exists (currently orphan)". `transport.capture_recording` is separately noted as effectively keycmd-only due to unmapped cgEvent (not an orphan, but binding is practically required).

  Matrix documented in `docs/SETUP.md §MIDIKeyCommands coverage` + linked from `manifest.json` description.
- [ ] **AC-3.5**: `docs/TROUBLESHOOTING.md` includes Logic 12.2 `.plist` import greyed-out symptom + honest manual MIDI Learn guidance. Migration guidance for users who followed pre-v3.1.4 SETUP.
- [ ] **AC-3.6**: Remove all misleading "Import" guidance from the following 4 files:
  - `Scripts/install.sh` (line ~235 Import guidance)
  - `Scripts/install-keycmds.sh` (output message)
  - `Scripts/keycmd-preset.plist` header comment
  - `docs/SETUP.md` (relevant section)

### US-4: Homebrew install on CLT-only host
**As a** user with Command Line Tools but no full Xcode, **I want** `brew install logic-pro-mcp` to proceed without being blocked, **so that** the ADHOC binary downloads and installs normally.

**Acceptance Criteria:**
- [ ] **AC-4.1**: The `depends_on xcode: ["15.0", :build]` line is removed from `Formula/logic-pro-mcp.rb`. Comment added: "ADHOC pre-built binary download — no source-build, no Xcode dependency. Source build via Package.swift requires Xcode 15.0+ but is not the supported install path."
- [ ] **AC-4.2**: `depends_on :macos => :sonoma` remains (runtime OS requirement).
- [ ] **AC-4.3**: Formula `test do` block (`shell_output "#{bin}/LogicProMCP --check-permissions"`) is retained — must pass without Xcode.
- [ ] **AC-4.4**: `brew audit --strict --new-formula Formula/logic-pro-mcp.rb` passes locally. The local verification command is documented in release notes.
- [ ] **AC-4.5**: `brew style Formula/logic-pro-mcp.rb` passes locally.

### US-5: Honest channel readiness reporting
**As an** AI agent reading `logic_system.health`, **I want** the MIDIKeyCommands channel detail to honestly report redundancy, required manual setup, and channel-only ops, **so that** I avoid the mistake of trusting the channel and sending unmapped commands.

**Acceptance Criteria:**
- [ ] **AC-5.1 (v0.3 corrected)**: `MIDIKeyCommands` channel health `detail` message includes:
  - Virtual MIDI port status ("`LogicProMCP-KeyCmd-Internal` is ready")
  - "Manual MIDI Learn required — see docs/SETUP.md §<section>"
  - "Most preset operations are covered by logic_edit / logic_project / logic_navigate / logic_tracks / logic_transport — see audited coverage matrix in SETUP.md"
  - "Effectively keycmd-only (cgEvent fallback unmapped): `transport.capture_recording`. Manual MIDI Learn binding required for actual function activation."
  - "Orphan ops in mappingTable (no MCP tool currently exposes call path): `note.up_semitone`, `note.up_octave`, `note.down_semitone`, `note.down_octave`, `view.toggle_smart_controls`, `view.toggle_plugin_windows`, `view.toggle_automation` (CC 57; distinct from `automation.toggle_view` CC 85). Manual binding possible but MCP has no caller path; tracked in NG6 follow-up."
- [ ] **AC-5.2**: `verification_status` remains `manual_validation_required` (no change to the fact that live verification is impossible). `available: true`, `ready: false` unchanged.
- [ ] **AC-5.3**: Channel itself is not deprecated (backward compat for users who have completed manual binding).
- [ ] **AC-5.4**: Health detail length < 1 KB per channel (envelope size validated by unit test).

## 4. Technical Design

### 4.1 Architecture Overview (v0.2 — Dispatcher-level direct routing)

```
                 ┌─────────────────────────────────────────┐
                 │ MIDIDispatcher (logic_midi)             │
                 │   send_cc / send_note / send_chord /    │
                 │   send_program_change / pitch_bend /    │
                 │   send_aftertouch / play_sequence /     │
                 │   record_sequence                       │
                 │                                         │
                 │ 1) port enum validation                 │
                 │    ("midi" | "keycmd"; default "midi")  │
                 │ 2) channel 1-based validation           │
                 │    (1..16, integer; reject 0/17+/float) │
                 │ 3) operation key branching:              │
                 │    port="midi"   → "midi.send_cc"       │
                 │    port="keycmd" → "midi.send_cc.keycmd"│
                 └────────────┬────────────────────────────┘
                              │
                              ▼
                 ┌─────────────────────────────────────┐
                 │ ChannelRouter.routingTable          │
                 │   "midi.send_cc": [.coreMIDI]       │
                 │   "midi.send_cc.keycmd":            │
                 │       [.midiKeyCommands]            │
                 │   ... (7 entries × 2 ports = 14;   │
                 │         record_sequence excluded    │
                 │         per NG7)                    │
                 │                                     │
                 │ Single-channel direct routing —     │
                 │ no fallthrough / terminal State C   │
                 │ conflicts                           │
                 └────────────┬────────────────────────┘
                              │
                ┌─────────────┴─────────────┐
                ▼                           ▼
    ┌──────────────────────┐   ┌──────────────────────────┐
    │ CoreMIDIChannel      │   │ MIDIKeyCommandsChannel   │
    │ engine →             │   │ transport →              │
    │ MIDI-Internal        │   │ KeyCmd-Internal          │
    └──────────────────────┘   └──────────────────────────┘
```

**Routing decisions (v0.3 — readiness bypass added)**:

1. MIDIDispatcher performs `port` parameter enum validation
2. If unspecified, defaults to `"midi"`
3. Branches directly to operation key `"midi.send_cc"` or `"midi.send_cc.keycmd"` (suffix pattern adopted — dynamic dictionary option discarded)
4. Add static entries to ChannelRouter.routingTable — **7 ops × 2 ports = 14 routing entries** (record_sequence excluded, NG7)
5. Add `midi.send_*.keycmd` operation cases to MIDIKeyCommandsChannel.execute (new direct-send path bypassing mappingTable)
6. **(v0.3 new)** Add `bypassReadinessOps: Set<String>` field to ChannelRouter. Register **7 ops × keycmd suffix only** — `["midi.send_cc.keycmd", "midi.send_note.keycmd", "midi.send_chord.keycmd", "midi.send_program_change.keycmd", "midi.send_pitch_bend.keycmd", "midi.send_aftertouch.keycmd", "midi.play_sequence.keycmd"]`. The readiness gate in `route()` passes operations in this set even when `ready: false` (even for `manual_validation_required` channels).
7. **(v0.4 new — Loop 3 Boomer P1-2 resolved)** In the `available: false` branch (virtual port not created), ChannelRouter returns `HonestContract.encodeStateC(error: .portUnavailable, hint: health.detail, extras: ["operation": op])` directly. `.portUnavailable` is registered in `terminalErrorCodes` so it is not wrapped in the fallback chain (does not pass to next channel). Normal ops retain existing `lastError` accumulation + "All channels exhausted" message (backward compat).

**Readiness bypass rationale (v0.4 chicken-and-egg framing — Loop 3 Guardian P2-2 resolved)**: Manual MIDI Learn seeding is by definition the step *before* channel approval (before `--approve-channel MIDIKeyCommands` is called). When a user first starts v3.1.5 → KeyCmd channel is `available:true / ready:false` (manual_validation_required) → without the bypass, no `*.keycmd` op can execute → Manual MIDI Learn binding itself cannot begin. **Chicken-and-egg**: without the bypass, there is no way for the user to create the binding needed to activate the channel. The bypass is the only mechanism to break this lock-in. After `--approve-channel` is called and `runtimeReady` is set, the bypass has no effect (readiness gate passes anyway). Normal routing (`midi.send_cc` → coreMIDI primary) retains the readiness check as-is.

**ScripterChannel excluded (NG5)**: `port: "scripter"` option is out of scope for v3.1.5. ScripterChannel handles only plugin parameter transmission — different transport and scope.

**record_sequence excluded (NG7)**: SMF import path (owned by TrackDispatcher), unrelated to KeyCmd port. Providing `port` input is rejected at dispatcher-level enum validation with invalid_params.

### 4.2 Data Model Changes
None. Code-level changes only. Adding entries to routingTable is an in-memory dictionary operation.

### 4.3 API Design

#### Changed: `logic_midi.send_*` 6 ops + `play_sequence` + `record_sequence`

**Previous (v3.1.4)**:
```jsonc
{
  "controller": 30,        // 0..127
  "value": 127,            // 0..127
  "channel": 16            // 0..16 — 16 wraps to wire 0 (off-by-one)
                            // pitch_bend/aftertouch have no validation (UInt8 raw)
}
```

**v3.1.5**:
```jsonc
{
  "controller": 30,        // 0..127 — unchanged
  "value": 127,            // 0..127 — unchanged
  "channel": 16,           // 1..16 (BREAKING: 0/17+/float now invalid_params)
  "port": "keycmd"         // optional, default "midi"
                            // values: "midi" | "keycmd"
                            // "scripter" deferred (NG5)
}
```

#### Dispatcher change specification

`Sources/LogicProMCP/Dispatchers/MIDIDispatcher.swift` changes:

```swift
// New helper
private static func validatePort(_ params: [String: Value]) -> Result<String, String> {
    let port = stringParam(params, "port", default: "midi")
    let validPorts = ["midi", "keycmd"]
    guard validPorts.contains(port) else {
        return .failure("port must be one of: \(validPorts.joined(separator: ", "))")
    }
    return .success(port)
}

private static func validateMidiChannel(_ params: [String: Value]) -> Result<UInt8, String> {
    // v0.3 strict integer check — reject floats like 1.5
    // Value type case-switch needed because Value.intValue accepts JSON int
    // but JSON double (`1.5`) returns nil, then stringValue also nil →
    // fall-through to default (silent corruption — AC-2.4 violation).
    guard let raw = params["channel"] else {
        // optional — default to channel 1 (1-based)
        return .success(0) // wire byte; Ch 1 in 1-based
    }
    let intCandidate: Int? = {
        switch raw {
        case .int(let n): return n
        case .double(let f):
            // accept whole-number doubles (1.0), reject fractional (1.5)
            return Int(exactly: f)
        case .string(let s): return Int(s)
        default: return nil
        }
    }()
    guard let v = intCandidate else {
        return .failure("channel must be integer 1..16 (1-based)")
    }
    guard (1...16).contains(v) else {
        return .failure("channel must be integer 1..16 (1-based)")
    }
    return .success(UInt8(v - 1)) // wire nibble 0..15
}

private static func operationKey(base: String, port: String) -> String {
    return port == "midi" ? base : "\(base).\(port)"
}

// case "send_cc" change
case "send_cc":
    switch validatePort(params) {
    case .failure(let msg): return toolTextResult(HonestContract.encodeStateC(error: .invalidParams, hint: msg, ...), isError: true)
    case .success(let port):
        switch validateMidiChannel(params) {
        case .failure(let msg): return toolTextResult(HonestContract.encodeStateC(error: .invalidParams, hint: msg, ...), isError: true)
        case .success(let wireChannel):
            return await routedTextResult(router, operation: operationKey(base: "midi.send_cc", port: port), params: [
                "controller": String(intParam(params, "controller")),
                "value": String(intParam(params, "value")),
                "channel": String(wireChannel),  // wire byte 0..15
            ])
        }
    }
// Same pattern for all 6 send_* ops + play_sequence — record_sequence is NG7: providing port input returns invalid_params at dispatcher-level (E14, AC-1.6)
```

#### ChannelRouter change specification

Add to `Sources/LogicProMCP/Channels/ChannelRouter.swift` `routingTable`:

```swift
"midi.send_cc": [.coreMIDI],
"midi.send_cc.keycmd": [.midiKeyCommands],
"midi.send_note": [.coreMIDI],
"midi.send_note.keycmd": [.midiKeyCommands],
// ... 8 ops × 2 ports
```

#### MIDIKeyCommandsChannel change specification

Add new cases to `Sources/LogicProMCP/Channels/MIDIKeyCommandsChannel.swift`:

```swift
func execute(operation: String, params: [String: String]) async -> ChannelResult {
    // Existing mappingTable lookup logic preserved
    // New case — direct MIDI send via KeyCmd transport (for manual MIDI Learn seeding)
    switch operation {
    case "midi.send_cc.keycmd":
        // Construct wire bytes directly, call transport.send
        // HC envelope (State B readback_unavailable — KeyCmd transport has no echo)
    case "midi.send_note.keycmd":
        // ...
    // 8 ops
    default:
        // Existing mappingTable lookup
    }
}
```

#### Tool description change

Update `MIDIDispatcher.swift:7` description:
```
"... send_cc/program_change/pitch_bend/aftertouch -> controller payloads (channel: 1..16 (1-based), port: \"midi\"|\"keycmd\" default \"midi\"); ..."
```

| Method | Operation key (port="midi") | Operation key (port="keycmd") |
|--------|-----------------------------|-------------------------------|
| send_cc | midi.send_cc | midi.send_cc.keycmd |
| send_note | midi.send_note | midi.send_note.keycmd |
| send_chord | midi.send_chord | midi.send_chord.keycmd |
| send_program_change | midi.send_program_change | midi.send_program_change.keycmd |
| send_pitch_bend | midi.send_pitch_bend | midi.send_pitch_bend.keycmd |
| send_aftertouch | midi.send_aftertouch | midi.send_aftertouch.keycmd |
| play_sequence | midi.play_sequence | midi.play_sequence.keycmd |

> **record_sequence (v0.3 NG7)**: SMF import path, owned by TrackDispatcher, KeyCmd port has no meaning. Providing `port` input is rejected at dispatcher-level validation with invalid_params. Channel 1-based encoding is applied to `record_sequence` in v3.1.5 via the `NoteSequenceParser` API change (below).

#### TrackDispatcher change specification (v0.3 new)

`Sources/LogicProMCP/Dispatchers/TrackDispatcher.swift` (record_sequence entry point):
- `record_sequence` case rejects `port` parameter input with invalid_params (NG7).
- `notes` string parsing is affected by the `NoteSequenceParser.parse(notes:)` API change — new `Result<[ParsedNote], NoteSequenceParseError>` type must be handled.

#### NoteSequenceParser API change (v0.3 new)

`Sources/LogicProMCP/MIDI/NoteSequenceParser.swift`:

```swift
// Previous (v3.1.4):
static func parse(_ notes: String) -> [ParsedNote]
// New (v3.1.5):
enum NoteSequenceParseError: Error {
    case channelOutOfRange(segment: String, value: Int)
    case invalidPitch(segment: String)
    case invalidTiming(segment: String)
    // ...
}
static func parse(_ notes: String) -> Result<[ParsedNote], NoteSequenceParseError>

// ParsedNote.channel field semantics change:
// Previous: UInt8 // 0..15 (wire value)
// New:      UInt8 // 0..15 (wire value) — input is converted from 1..16 (1-based)
//           partial parse no longer silently default-handles invalid segments
```

Call sites requiring changes:
- `Sources/LogicProMCP/Dispatchers/TrackDispatcher.swift` — `record_sequence` SMF generation
- `Sources/LogicProMCP/Channels/CoreMIDIChannel.swift` — `play_sequence` real-time playback (line ~279)
- Both must return State C `invalid_params` + hint on `.failure`.

### 4.4 Key Technical Decisions (v0.2 updated)

| # | Decision | Options Considered | Chosen | Rationale |
|---|----------|-------------------|--------|-----------|
| D1 | Port routing location | (A) Channel-side fallthrough / (B) Dispatcher-level direct | **B** | (A) conflicts with ChannelRouter terminal State C suppression + manual_validation_required skip. P1 found in v0.1 review. Dispatcher-level makes routing semantics clear. |
| D2 | Channel 1..16 enforcement | (A) Strict reject 0 / (B) Lenient — 0 also maps to ch 1 / (C) Dual-mode (deprecation cycle) | **A** | Precise fix for Issue #1-3. Prevents silent wrong-channel recurrence. (C) is attractive but ending in a single release cycle is cleaner. |
| D3 | Backward compat for `port` | (A) Required param / (B) Optional default "midi" | **B** | Zero impact on existing callers + identical error message wording. |
| D4 | Port enum values | (A) `"midi"|"keycmd"|"scripter"` / (B) `"midi"|"keycmd"` only | **B** | ScripterChannel is plugin param-only, no responsibility for midi.send_*. Excluded from v3.1.5 scope. |
| D5 | MIDIKeyCommands channel handling | (A) Deprecate + remove / (B) Deprecate flag only / (C) Retain + audited matrix | **C** | Protect external users who have completed manual binding. channel-only ops (note.up_*/down_*) exist. Honest reporting via health detail. |
| D6 | 1-based migration | (A) Silent / (B) BREAKING + CHANGELOG | **B** | Silent is a debugging nightmare. CHANGELOG BEFORE/AFTER table + Issue #1 auto-comment + tool description inline. |
| D7 | Homebrew xcode dependency | (A) Full removal / (B) `:optional` | **A** | ADHOC release is a pre-built binary. Only `depends_on :macos => :sonoma` is needed. |
| D8 | Channel encoding scope | (A) send_* 6 ops only / (B) send_* + play_sequence + record_sequence | **B** | Encoding consistency within the same dispatcher. P1 found in PRD v0.1 review. |
| D9 | "All covered" docs phrasing | (A) Simple text / (B) Audited coverage matrix | **B** | Some mappingTable entries have no other dispatcher path (note.up_*). Honest matrix required. |
| D10 | Issue #1 automation | (A) Manual comment / (B) Add gh comment + close step to release.sh | **B** | Prevents missing external user communication — automated. |

## 5. Edge Cases & Error Handling (v0.2 expanded)

| # | Scenario | Expected Behavior | Severity |
|---|----------|-------------------|----------|
| E1 | `port: "foo"` (invalid) | Dispatcher-level validation → State C `invalid_params` + hint: "port must be one of: midi, keycmd" | P1 |
| E2 | `port: "scripter"` | Same as E1 (NG5 — unsupported in v3.1.5) + hint includes "scripter port deferred to future release" | P2 |
| E3 | `port: "midi"` explicit + existing callers | 100% identical to prior behavior (CoreMIDIChannel routing, same error message wording) | P0 |
| E4 | `channel: 0` | State C `invalid_params` + hint: "channel must be integer 1..16 (1-based)" — BREAKING | P1 |
| E5 | `channel: 17` | Same hint as E4 | P1 |
| E6 | `channel: 1.5` (float) | Strict integer parser → State C `invalid_params` + hint | P2 |
| E7 (v0.3 corrected) | `port: "keycmd"` + KeyCmd virtual port not initialized (startup race) | `MIDIKeyCommandsChannel.healthCheck().available == false` or `transport.readiness().available == false` → State C `port_unavailable` (new `HonestContract.FailureError` case + registered in terminalErrorCodes) + hint: "LogicProMCP-KeyCmd-Internal not yet published; check logic_system.health" | P1 |
| E8 (v0.3 corrected) | `port: "keycmd"` + channel is `manual_validation_required` (user not yet approved) | **router-level bypass allowlist** (AC-1.7) applied → dispatcher-level direct routing passes readiness gate and reaches execute. If KeyCmd virtual port is published, transmission succeeds. Normal routing (`midi.send_cc` → coreMIDI primary) retains readiness check as-is. | P1 |
| E9 | External user who completed manual binding on v3.1.4 with `channel:16` — wire changes in v3.1.5 | (a) If v3.1.4 binding with ch16 input → wire 0x?0 (Ch 1) match, it breaks in v3.1.5. (b) If ch16 input intended to match Ch 16 binding, the v3.1.4 wire-wrap → ch1 send would not have worked. So only (a) is possible. Documented in CHANGELOG BEFORE/AFTER table + users advised "one rebind cycle required after v3.1.5 upgrade". | P1 |
| E10 | Homebrew formula `xcode` removal + brew audit | `brew audit --strict --new-formula Formula/logic-pro-mcp.rb` passes locally | P1 |
| E11 | brew bottle CI re-build (if present) | ADHOC binary download path documented — bottle/source-build explicitly unsupported | P2 |
| E12 | New user follows updated SETUP.md | Manual MIDI Learn 2 examples → at least 2 bindings succeed + 5–25 min estimate visible | P1 |
| E13 | Health detail becomes large enough to exceed JSON envelope size | Current envelope ~200 bytes → new detail ~600 bytes expected (audited matrix link included). Unit test validates < 1KB limit. | P2 |
| E14 (v0.3 changed) | `port` input for `record_sequence` / `mmc_*` / `send_sysex` / `step_input` / `create_virtual_port` | Dispatcher-level enum validation immediately rejects → State C `invalid_params` + hint: `"port parameter not supported for <op_name>"`. Silent ignore removed (NG7/NG8). | P2 |
| E15 | `gh issue comment 1` fails during release.sh | Release itself completes as success + warning. Issue comment has manual fallback (release notes contains link). | P2 |

## 6. Security & Permissions
No changes. All dispatch is server-local. `port` enum string membership check has no permission bypass / DoS vector.

## 7. Performance & Monitoring

| Metric | Target | Measurement |
|--------|--------|-------------|
| `send_cc` call latency (p95) | < 5ms (CoreMIDI port write) | Live verification |
| `port` branch overhead | < 0.1ms (dispatcher-level enum check) | Unit test measurement |
| Health detail size | < 1 KB per channel | E13 unit test |

### 7.1 Monitoring & Alerting
- **No remote telemetry**: logic-pro-mcp is server-local + stdio MCP. Log.debug stderr only.
- `port: "keycmd"` usage frequency depends on user self-reporting.
- Channel routing failures produce router-level warn log (subsystem: "router").

## 8. Testing Strategy

### 8.1 Unit Tests (TDD Spec)
- `MIDIDispatcherSendCCPortTests.swift` (NEW)
  - testSendCCDefaultPortRoutesToMidiSendCCOperation
  - testSendCCKeycmdPortRoutesToMidiSendCCKeycmdOperation
  - testSendCCInvalidPortReturnsStateCInvalidParams
  - testSendCCScripterPortRejectedAsNotSupported (E2)
- `MIDIDispatcherChannelEncodingTests.swift` (NEW)
  - testChannel1MapsToWireZero
  - testChannel16MapsToWireFifteen
  - testChannel0Rejected
  - testChannel17Rejected
  - testFloatChannelRejected (E6)
  - testMissingChannelDefaultsToCh1Wire0
- `MIDIDispatcherEntryPointConsistencyTests.swift` (NEW, v0.4 corrected)
  - testAllSendOpsAcceptPortParam (**7 ops × 2 ports = 14 cases** parametrized — record_sequence excluded, NG7)
  - testAllSendOpsValidateChannel1Based
  - testRecordSequenceRejectsPortParam (E14, NG7 — silent ignore removed, invalid_params reject)
  - testMmcOpsRejectPortParam (NG8 — mmc_*/sysex/step_input/create_virtual_port)
  - testRoutingTableInvariant — validates that every `^midi\..*\.keycmd$` routing key is included in the `bypassReadinessOps` set (Loop 3 Guardian P2-1 fix — prevents parallel-list trap)
- `NoteSequenceParserTests.swift` (extended)
  - testNoteSequenceChChannelIs1Based
  - testNoteSequenceCh0Rejected
  - testNoteSequenceCh17Rejected
- `MIDIKeyCommandsChannelDirectSendTests.swift` (NEW)
  - testKeyCmdChannelHandlesSendCCKeycmdOperation
  - testKeyCmdChannelTransportNotPublishedReturnsPortUnavailable (E7)
- `ChannelRouterRoutingTableTests.swift` (extended)
  - testRoutingTableContainsAllSendOpsKeycmdVariants
- `HealthDispatcherTests.swift` (extended)
  - testKeyCmdChannelDetailIncludesManualLearnHint
  - testKeyCmdChannelDetailMentionsCoverageMatrix
  - testKeyCmdChannelDetailListsChannelOnlyOps
  - testKeyCmdChannelDetailUnderOneKB (E13)
- `BackwardCompatRegressionTests.swift` (NEW)
  - testSendCCWithoutPortMatchesPriorBehavior (E3 — string-equality of error messages)
  - testRoutingTableMidiSendCCKeyUnchanged

### 8.2 Integration Tests
- All `port`-unspecified calls in existing `MIDIDispatcherTests` PASS (backward compat regression).
- `ChannelRouterTests` extended to validate new routing entries.

### 8.3 Edge Case Tests
- E1–E15 all covered by unit test cases.
- E9 manual binding compat — live verification only (Isaac's environment + reporter's environment).
- E10/E11 brew test — local `brew audit --strict --new-formula` passes + verified in Isaac CI/dev environment.
- E12 docs — review-time validation (Phase 6 strategist+guardian).

### 8.4 Live Verification Required (v0.2 new, v0.3 release-blocker criteria added)
The following scenarios cannot be covered by unit tests → live verification required before release:
1. **AC-1.1 live**: Logic 12.2 Controller Assignments → Learn Mode active → MCP transmits with `port:"keycmd"` → confirm `LogicProMCP-KeyCmd-Internal` captured as input.
2. **AC-2.1 live**: Transmit `channel:16` → confirm Logic UI displays Ch 16.
3. **AC-3.2 live**: Follow the Manual MIDI Learn 2 example steps from SETUP.md → confirm binding succeeds.
4. **AC-4.1/4.4/4.5 live**: Simulate CLT-only host or use Isaac's environment → confirm `brew install logic-pro-mcp` succeeds.
5. **E9 live**: In environment with v3.1.4 + completed manual binding → upgrade to v3.1.5 → document which bindings work / which require rebinding.

**Release blocker criteria (v0.3 new)**:
- Scenarios **1, 2, 4 must PASS** — release blocked otherwise. If failure, v3.1.5 release postponed.
- Scenario **3** — Isaac follow-along once PASS + reporter re-verification by Issue close time. If any step is ambiguous, revise docs and re-verify.
- Scenario **5** — Acceptable with migration note in TROUBLESHOOTING.md. Not a release blocker (docs ship + users advised to rebind).

## 9. Rollout Plan

### 9.1 Migration Strategy (v0.2 strengthened)
- v3.1.4 → v3.1.5 binary auto-compatible (backward compat for unspecified `port`).
- **BREAKING for channel encoding**:
  - CHANGELOG BEFORE/AFTER table (AC-2.6)
  - GitHub Release notes prominent `### ⚠️ BREAKING` section + migration table
  - Issue #1 auto-comment via `Scripts/release.sh` (AC-2.6, G7)
  - Issue #1 auto-close
  - Tool description (`MIDIDispatcher.description`) inline "channel: 1..16 (1-based)"
  - `LogicProMCP --check-permissions` output includes v3.1.5 BREAKING one-line reminder (once only)
- Homebrew formula change: auto-updated with v3.1.5 release (release.sh updates Formula sha256). Brew audit local validation (AC-4.4).

### 9.2 Feature Flag
N/A. All changes apply immediately in v3.1.5.

### 9.3 Rollback Plan
- Users can downgrade to v3.1.4 — v3.1.4 tag is preserved in the Homebrew tap.
- If channel encoding regression is discovered, v3.1.6 hotfix.
- If manual binding users break (E9): a 1-page "manual binding reconstruction after v3.1.5 upgrade" guide in docs/TROUBLESHOOTING.md.

## 10. Dependencies & Risks (v0.2 expanded)

### 10.1 Dependencies
| Dependency | Owner | Status | Risk if Delayed |
|-----------|-------|--------|-----------------|
| MIDIKeyCommandsChannel `KeyCmdTransportProtocol` | Internal | Existing code | None (transport.send available) |
| ChannelRouter routingTable in-memory | Internal | Existing code | None |
| HonestContract `FailureError` enum extension (`portUnavailable` new case) | Internal | Requires new addition | Assumes external envelope parsers gracefully ignore unknown reasons (low risk) |
| `gh` CLI authenticated for Issue #1 comment | Isaac local | Active | release.sh automation — manual fallback on failure (E15) |
| Homebrew tap repo write access | Isaac | Active | release.sh auto-push |

### 10.2 Risks
| # | Risk | Probability | Impact | Mitigation |
|---|------|------------|--------|------------|
| R1 | Channel encoding change breaks external manual-binding users (E9) | Medium | High | CHANGELOG BEFORE/AFTER table + Issue #1 auto-comment + reporter advance notice + TROUBLESHOOTING.md migration |
| R2 | Dispatcher-level routing causes routingTable key proliferation (16 entries) | Low | Low | Suffix pattern is consistent — readability OK. Unit tests validate all entries |
| R3 | Docs rewrite contains ambiguous steps | Medium | Medium | Phase 6 strategist+guardian review + live verification (AC-3.2 step-by-step) |
| R4 | Homebrew formula change fails brew audit | Low | Low | Local `brew audit --strict --new-formula` + `brew style` validation (AC-4.4/4.5) |
| R5 | brew bottle CI re-build blocked (if present) | Low | Low | ADHOC binary download path documented — bottle/source-build explicitly unsupported (E11) |
| R6 | Port enum future extension (e.g., adding `"scripter"`) | Low | Low | Enum is string-based — future extension only requires adding a new case + routingTable entry |
| R7 | HonestContract FailureError extension breaks external envelope parsers | Low | Medium | "Unknown reason gracefully ignored" assumption documented in CHANGELOG |
| R8 (v0.3 strengthened) | Issue #1 auto-comment floods reporter notifications (v3.1.6+ re-commenting on reopen) | Low | Low | release.sh checks `gh issue view 1 --json state` — only comments + closes if OPEN. If CLOSED, skip. If reporter reopens after v3.1.5 closes, future releases comment on new issue instead (auto-reclose prohibited). |
| R9 | Manual MIDI Learn 2 examples insufficient | Medium | Medium | Isaac follows along once + requests reporter follow-along in docs review |

## 11. Success Metrics

| Metric | Baseline | Target | Measurement Method |
|--------|----------|--------|--------------------|
| GitHub Issue #1 closure | OPEN | CLOSED with v3.1.5 release link | Issue tracker |
| New user setup time-to-first-success | ~25 min (reporter) | ≤ 10 min (with clearer manual MIDI Learn guidance) | Reporter re-test request |
| `port:"keycmd"` adoption | N/A | 1+ external use cases (within 3 months) | User self-reporting |
| Channel encoding user confusion | 1+ reported | 0 (BREAKING change documented + invalid_params hint) | Future GitHub issues |
| Tests: pass count | 917 (post-v3.1.5 thomas-doesburg) | 1000+ (+85 tests minimum across T1–T8) | swift test --no-parallel |
| Tests: backward compat regression | 0 fail | 0 fail | BackwardCompatRegressionTests |

## 12. Open Questions (v0.2 updated)

- [x] **OQ-1**: `port` parameter value naming — `"midi"` is generic but user-friendly. Decision retained. Tool description inline: "default port (CoreMIDI virtual source for general MIDI output)".
- [x] **OQ-2**: Health detail length. Decision: single `detail` string + < 1 KB limit (E13).
- [x] **OQ-3**: Are all 48 command bindings mandatory? Decision: NO. Minimal path (channel-only ops only) recommended + audited matrix documented.
- [x] **OQ-4 (v0.2 new)**: Future addition of `port: "scripter"` — ScripterChannel extension? Decision: review in separate PRD. Documented in v3.1.5 NG5.
- [x] **OQ-5 (v0.2 new)**: `record_sequence` port has no meaning — silent ignore vs reject? Decision: warning log + ignore (E14, backward compat).
- [x] **OQ-6 (v0.2 new)**: Add dispatcher paths for channel-only ops like `note.up_*` / `view.toggle_*`? Decision: NG6, separate follow-up issue.
- [x] **OQ-7 (v0.3 decided)**: Add `portUnavailable` case to HonestContract `FailureError` — minor bump (v3.1.5) enum addition OK + registered in `terminalErrorCodes` (prevents router fallback chain wrapping). CHANGELOG: "New FailureError: `port_unavailable` (terminal). External envelope parsers must gracefully ignore unknown reasons; documented as part of HonestContract minor evolution policy." Migration: no existing v3.1.4 code triggers `port_unavailable` path — addition only, no existing response changes.

---
