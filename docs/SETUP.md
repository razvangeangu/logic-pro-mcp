# Setup Guide

Complete installation, Logic Pro integration, and verification. Should take ~10 minutes on a fresh machine.

## Requirements

- macOS 14+ (Sonoma, Sequoia)
- Logic Pro 12.0.1+
- Apple Silicon (arm64) native; Intel (x86_64) supported via Rosetta 2 (install from source with `swift build` for a native Intel build)
- Claude Code or Claude Desktop

---

## 1. Install the Binary

### Option A — Homebrew (recommended)

```bash
brew tap MongLong0214/logic-pro-mcp https://github.com/MongLong0214/logic-pro-mcp
brew install logic-pro-mcp
```

Homebrew pins both the release tarball URL and its SHA256 in the formula, and Homebrew itself is a trusted delivery channel with its own signature chain. Use this path whenever possible.

### Option B — Download-inspect-run one-line installer

The installer is **fail-closed by default**: it refuses to run without explicit SHA256 + Team ID pins. Inspect the script first, verify the hash from the release's `SHA256SUMS.txt`, then execute:

```bash
curl -fsSL https://raw.githubusercontent.com/MongLong0214/logic-pro-mcp/v3.0.2/Scripts/install.sh -o install.sh
# inspect install.sh, then:
LOGIC_PRO_MCP_SHA256=<hex from release SHA256SUMS.txt> \
LOGIC_PRO_MCP_TEAM_ID=ADHOC \
bash install.sh
```

If you knowingly accept same-origin provenance (hash + Team ID fetched from the same release as the binary), opt in:

```bash
LOGIC_PRO_MCP_ALLOW_SAME_ORIGIN=1 \
bash <(curl -fsSL https://raw.githubusercontent.com/MongLong0214/logic-pro-mcp/v3.0.2/Scripts/install.sh)
```

See [SECURITY.md §Installer trust model](../SECURITY.md#installer-trust-model) for the threat model.

### Option C — Build from source

```bash
git clone https://github.com/MongLong0214/logic-pro-mcp.git
cd logic-pro-mcp
swift build -c release
codesign --force --sign - .build/release/LogicProMCP
sudo cp .build/release/LogicProMCP /usr/local/bin/
claude mcp add --scope user logic-pro -- LogicProMCP
```

---

## 2. Grant macOS Permissions

Open **System Settings → Privacy & Security**:

1. **Accessibility** → add `LogicProMCP` (click `+` → `/usr/local/bin/LogicProMCP`) → toggle ON
2. **Automation** → find `LogicProMCP` → check the `Logic Pro` checkbox

Verify:

```bash
LogicProMCP --check-permissions
# Expected: Accessibility: granted / Automation (Logic Pro): granted
```

---

## 3. Register MCU Control Surface (mandatory for mixer control)

The MCP server controls Logic Pro's mixer via the Mackie Control Universal (MCU) protocol over a virtual MIDI port.

> ⚠️ **MCU registration is the single most failure-prone step** — if you skip it, mixer writes will fail with "All channels exhausted" errors. Follow it exactly.

1. Launch **Logic Pro**. The MCP server auto-starts when Claude Code connects.
2. Menu: **Logic Pro → Control Surfaces → Setup…** (KR: `컨트롤 서피스 → 설정…`)
3. Top-left menu: **New → Install…** (KR: `신규 → 설치…`)
4. Find **Mackie Designs → Mackie Control** → click **Add**
5. Click the newly added **Mackie Control** device card
6. In the Inspector panel, set **BOTH** In and Out ports to `LogicProMCP-MCU-Internal`
7. Close the setup window (saves automatically)

Verify in Claude:

> "Check Logic Pro MCP health and report MCU status."

Expected:

```json
{ "connected": true, "registered_as_device": true, "feedback_stale": false }
```

---

## 4. MIDIKeyCommands (optional — only if you need channel-only ops)

> ⚠️ **Logic Pro 12.2+ does NOT accept the legacy `.plist` Key Commands import.** Earlier versions of this guide instructed `Logic Pro → Key Commands → Import…` and selecting `keycmd-preset.plist`. On Logic 12.2 the Import menu is grayed out and the import will not happen — that path was never reliable on 12.2 and is removed in v3.1.6. The `.plist` file is retained **only as a CC→Command mapping reference** for the manual MIDI Learn workflow below.

### Do you actually need this?

In v3.1.6 most preset operations are routed via the regular tools — you do **not** need to bind anything manually. The handful of operations that *only* reach Logic via MIDI Key Commands are listed in the **Audited coverage matrix** below; if you don't use those ops, **skip this section entirely**.

| Time budget | Scope |
|-------------|-------|
| ~2 minutes  | Single channel-only op (e.g. `transport.capture_recording`) |
| ~5 minutes  | All channel-only / effectively-keycmd-only ops |
| ~25 minutes | Full coverage of all 48 mappingTable rows (overkill for almost everyone) |

### 4.1 Audited coverage matrix

Audited against `MIDIKeyCommandsChannel.swift` mappingTable + every dispatcher's routing table. **"requires keycmd binding?"** answers whether you actually have to do MIDI Learn for the op to work.

| `mappingTable` op (CC#)                                                                                    | Dispatcher entry exposing it           | Router primary fallback                  | Requires keycmd binding? |
|------------------------------------------------------------------------------------------------------------|----------------------------------------|------------------------------------------|--------------------------|
| `edit.undo (30)` / `redo (31)`                                                                             | `logic_edit.undo` / `.redo`            | accessibility, applescript               | NO — optional            |
| `edit.cut/copy/paste/select_all`                                                                           | `logic_edit`                           | accessibility, cgevent                   | NO — optional            |
| `edit.quantize/join/duplicate/split/normalize/delete/bounce_in_place`                                      | `logic_edit`                           | accessibility, cgevent                   | NO — optional            |
| `edit.toggle_step_input`                                                                                   | `logic_edit.toggle_step_input`         | midiKeyCommands, cgevent                 | RECOMMENDED              |
| `project.save / save_as / bounce`                                                                          | `logic_project`                        | applescript                              | NO — optional            |
| `transport.toggle_cycle (72)`                                                                              | `logic_transport.toggle_cycle`         | midiKeyCommands, accessibility           | RECOMMENDED              |
| `transport.capture_recording (73)`                                                                         | (no other dispatcher entry)            | midiKeyCommands only                     | YES                      |
| `transport.toggle_metronome / toggle_count_in (98/99)`                                                     | `logic_transport`                      | midiKeyCommands, accessibility           | RECOMMENDED              |
| `track.create_audio / create_instrument / create_external_midi / duplicate / delete / create_stack / create_drummer` | `logic_tracks`               | midiKeyCommands, cgevent                 | RECOMMENDED              |
| `view.toggle_mixer/piano_roll/library/inspector/score_editor/step_editor (50-51, 55-56, 59, 48)`           | `logic_navigate.toggle_view`           | midiKeyCommands, cgevent                 | RECOMMENDED              |
| `nav.goto_marker / create_marker / delete_marker / zoom_to_fit / set_zoom_level`                           | `logic_navigate`                       | midiKeyCommands, cgevent                 | RECOMMENDED              |
| `automation.set_mode (84)`                                                                                 | `logic_tracks.set_automation`          | mcu (primary), midiKeyCommands, cgevent  | RECOMMENDED              |
| `automation.toggle_view (85)`                                                                              | `logic_navigate.toggle_view {automation}` | midiKeyCommands, cgevent (`.key(0)`) | RECOMMENDED              |

#### Orphan ops (in mappingTable but no MCP tool currently exposes a call path)

These can be MIDI-Learned but no `logic_*` tool currently routes to them. Tracked as a follow-up issue; binding them today is purely speculative.

- `note.up_semitone (90)` / `note.down_semitone (91)` / `note.up_octave (92)` / `note.down_octave (93)`
- `view.toggle_smart_controls (54)` / `view.toggle_plugin_windows (58)` / `view.toggle_automation (CC 57 — distinct from CC 85 `automation.toggle_view`)`

#### Effectively-keycmd-only (cgEvent fallback unmapped)

- `transport.capture_recording (CC 73)` — `CGEventChannel` has no entry. Routing table reads `[.midiKeyCommands, .cgEvent]` but cgEvent is a no-op for this op, so manual MIDI Learn is the *only* way to make it fire.

### 4.2 Manual MIDI Learn — Example 1: `Edit > Undo` (CC 30, Ch 16)

> Total time: ~2 minutes per binding.

1. **Open Logic Pro and approve the keycmd port:**
   ```bash
   LogicProMCP --approve-channel MIDIKeyCommands --approval-note "Manual MIDI Learn — v3.1.6"
   ```
   This unblocks the `port:"keycmd"` routing in MCP. (You can revoke later with `--revoke-channel`.)

2. **Open Logic Pro's Key Commands editor:** `Logic Pro → Key Commands → Edit…` (⌥K). The window has a search field at the top right and a list of every command on the left.

3. **Find the command:** Type `Undo` into the search field. Click the row labelled exactly `Undo` (NOT `Undo Region/Event Position` etc.).

4. **Enter Learn mode:** With the row still selected, click the **Learn New Assignment** button at the bottom right of the window. The button highlights blue and Logic now listens for any incoming MIDI message.

5. **Send the CC from your MCP client** (e.g. Claude):
   > "Send CC 30 value 127 on channel 16 via the keycmd port."

   That maps to:
   ```jsonc
   logic_midi.send_cc {
     "controller": 30,
     "value": 127,
     "channel": 16,
     "port": "keycmd"
   }
   ```
   Logic should immediately display `Ch 16 / Controller #30` next to the command and exit Learn mode automatically.

6. **Save the assignment:** Click `Save As…` (or `Save` if you've saved this set before). Logic 12.2 stores assignments in its own binary `.logikcs` format inside the user `Key Commands` folder; **do not** try to edit it manually.

7. **Verify:** Send the CC again — Logic should perform Undo on the focused window. If nothing happens, return to step 4 and re-bind (Logic occasionally drops the first capture on a freshly-created port).

### 4.3 Manual MIDI Learn — Example 2: `Track > New Audio Track` (CC 20, Ch 16)

> Same flow, repeated to confirm the pattern.

1. Already approved the channel from §4.2 step 1? Skip. Otherwise approve as above.

2. `Logic Pro → Key Commands → Edit…` (⌥K). Search `New Audio Track`. Click the row.

3. Click **Learn New Assignment**.

4. From your MCP client:
   ```jsonc
   logic_midi.send_cc {
     "controller": 20,
     "value": 127,
     "channel": 16,
     "port": "keycmd"
   }
   ```

5. Click `Save Assignments`.

6. Verify by repeating the send — Logic should create a new audio track each time.

### 4.4 Channel cheat-sheet

`channel: 16` in MCP corresponds to **Ch 16** in Logic's UI (1-based). Pre-v3.1.6 the wire encoding was 0-based (`channel: 15` = Logic Ch 16); v3.1.6 normalizes the contract. See `CHANGELOG.md §[3.1.6]` for the migration table.

---

## 5. Install Scripter Insert (optional — for plugin parameter control)

Enables `set_plugin_param` for fine-grained plugin automation via CC 102-119.

1. In Logic Pro, select a Software Instrument track
2. Click the **MIDI FX** slot on the channel strip → select **Scripter**
3. In the Scripter window, click the **Script Editor** tab
4. Paste the contents of `Scripts/LogicProMCP-Scripter.js` into the editor
5. Click **Run Script**

Approve:

```bash
LogicProMCP --approve-channel Scripter --approval-note "Validated insertion on target track"
```

---

## 6. Verify Everything

Ask Claude:

> "Check Logic Pro MCP health."

Expected — all 7 channels `ready`:

```
- Accessibility ✓
- AppleScript ✓
- CoreMIDI ✓
- MCU ✓
- MIDIKeyCommands ✓ (if you completed step 4)
- Scripter ✓ (if you completed step 5)
- CGEvent ✓
```

If any channel is `manual_validation_required`, return to step 4 or 5 and complete the approval.

---

## Uninstall

```bash
Scripts/uninstall.sh

# Or manually:
sudo rm /usr/local/bin/LogicProMCP
claude mcp remove logic-pro
Scripts/uninstall-keycmds.sh   # restores original Key Commands
```

Inside Logic Pro, open **Control Surfaces → Setup…**, select the Mackie Control device, and press Delete.

---

## What's Next

- [API Reference](API.md) — full MCP tool surface
- [Troubleshooting](TROUBLESHOOTING.md) — common issues
- [Architecture](ARCHITECTURE.md) — how the 7-channel design works
