# Troubleshooting Guide

Diagnostic recipes for common issues, listed by symptom. Each entry gives the likely cause and a concrete fix.

For MCU-specific problems, see [SETUP.md §3](SETUP.md#3-register-mcu-control-surface-mandatory-for-mixer-control).

---

## Server Won't Start

### `claude mcp add` succeeds but server never responds

**Cause:** binary not on `PATH`, or permissions missing.

```bash
which LogicProMCP                                 # expect: /usr/local/bin/LogicProMCP
LogicProMCP --check-permissions                   # expect both granted
ls -l /usr/local/bin/LogicProMCP                  # expect executable bit set
```

If `--check-permissions` reports `NOT VERIFIABLE (Logic Pro not running)`, start Logic Pro once and retry.

### Server starts but `tools/list` returns empty / times out

**Cause:** stdio framing mismatch or server crashed during init.

Check stderr:
```bash
LogicProMCP 2>/tmp/mcp-stderr.txt < /dev/null &
sleep 2
kill %1
head -40 /tmp/mcp-stderr.txt
```

Look for lines like:
- `MIDIPortManager started` — CoreMIDI initialized
- `Accessibility channel started` — AX ready
- `Starting logic-pro-mcp v3.0.0 — 8 tools, 9 resources, 7 channels` — composition complete

If you see `AccessibilityError.notTrusted`, grant Accessibility permission.

---

## Permissions

### Accessibility denied

```
Accessibility: NOT GRANTED
  → System Settings > Privacy & Security > Accessibility → add your terminal app
```

**Fix:**
1. Open **System Settings → Privacy & Security → Accessibility**
2. Click **+** and add the parent process (e.g. `Terminal.app`, `Claude Code.app`, or your IDE).
3. Toggle the switch ON.
4. **Restart the MCP server** (Claude Code → toggle MCP off/on, or kill + restart terminal).

macOS caches trust per-bundle. Changes take effect only for processes started *after* the toggle.

### Automation denied

```
Automation (Logic Pro): NOT GRANTED
  → System Settings > Privacy & Security > Automation → allow control of Logic Pro
```

**Fix:**
1. With Logic Pro running, trigger any AppleScript operation (e.g. `logic_project is_running`).
2. macOS pops up a consent dialog: *"Terminal wants access to control Logic Pro"* — click **OK**.
3. If you clicked Deny previously: **System Settings → Privacy & Security → Automation → [your terminal] → Logic Pro** → toggle ON.
4. Restart the MCP server.

### Automation: `NOT VERIFIABLE`

**Cause:** Logic Pro is not running.

**Fix:** Launch Logic Pro once, then `LogicProMCP --check-permissions` again. Automation verification requires Logic Pro to be alive so the consent dialog can fire.

---

## Library (Sound Pack Enumeration — v2.2+)

### `scan_library` returns "Library panel not found"

**Cause:** Library panel isn't visible in Logic Pro.

Fix: Open a project, click any track, press ⌘L. Re-run `scan_library`. The Library must show a left column of categories (Bass, Orchestral, etc.).

### `set_instrument` silently loads instrument onto the wrong track

**Cause:** Track header isn't clickable because the track is scrolled off-screen.

Fix: Scroll the tracklist in Logic so the target track is visible. The MCP now emits `"Track not visible; scroll tracklist"` instead of clicking blindly.

### `set_instrument` fails with "Event-post permission required"

**Cause:** macOS 10.15+ requires **Post-Event access**, a capability granted alongside Accessibility. `CGPreflightPostEventAccess()` returned false.

Fix:
1. System Settings → Privacy & Security → Accessibility
2. Remove LogicProMCP, re-add it; macOS will prompt for event-post on first CGEvent.post.
3. Verify: `logic_system { command: "health" }` — expect `"post_event_access": true` under `permissions`.

### `resolve_path` returns `"No cached library scan; call scan_library first"`

**Cause:** `resolve_path` is cache-backed (read-only, zero AX clicks). No cache yet.

Fix: Run `scan_library` once. The in-memory cache persists until the MCP process restarts.

### Scan counts look low (e.g. Orchestral: 2)

**Cause:** Reflects what your Sound Library has **installed** — not a scanner bug. Logic Pro 12's Library is a flat 2-level browser; the scanner captures 100% of visible presets. Install more via Logic Pro → Sound Library → Download All Available Sounds.

---

## MCU / Mixer

### `mixer.set_volume` returns "All channels exhausted … MCU feedback not detected"

**Cause:** MCU control surface not registered in Logic Pro, or handshake failed.

**Fix:** See [SETUP.md §3](SETUP.md#3-register-mcu-control-surface-mandatory-for-mixer-control) — register `LogicProMCP-MCU-Internal` in **Control Surfaces → Setup**.

Mixer operations have **no fallback** — MCU registration is mandatory.

### MCU was registered but `health.mcu.feedback_stale: true`

**Cause:** Logic Pro isn't actively sending MCU feedback.

**Fix:**
1. Restart Logic Pro.
2. Re-open the Control Surface Setup window once (no changes needed — just open and close).
3. Click in the Logic Pro mixer area; movement should trigger feedback.
4. Check `health` again after 2 seconds.

### Mixer shows wrong track count

**Cause:** MCU banks in groups of 8. The visible "strip range" depends on `bank` position.

**Fix:** Use `logic_navigate goto_bar` or Logic Pro's bank buttons to move to the intended 8-track window. MCU inherently only surfaces 8 strips at a time to the external device.

---

## MIDI

### Virtual MIDI ports not visible in Logic Pro

**Cause:** MCP server not running when Logic Pro's dropdown was opened.

**Fix:** Start the MCP server **before** opening Logic Pro's MIDI port dropdown. If already open, close and reopen the dropdown — Logic refreshes the port list on open.

### `midi.send_note` succeeds but no sound in Logic Pro

**Cause:** No track in Logic Pro has its MIDI input set to `LogicProMCP-Out` (or the MCP server's CoreMIDI source).

**Fix:**
1. In Logic Pro, select an instrument track.
2. Set **Record Enable** (R button).
3. In track inspector, set **Input** to `LogicProMCP-Out` (or `All` to accept from any source).

Or use Scripter for deterministic plugin parameter control (no track routing needed).

### SysEx transmission fails

**Cause:** Bytes don't start with `F0` or don't end with `F7`.

**Fix:** MCU server validates F0/F7 framing. Pass bytes as either:
- `{"bytes": "F0 7F 7F 06 02 F7"}` (hex string, space-separated)
- `{"bytes": [240, 127, 127, 6, 2, 247]}` (integer array)

---

## MIDIKeyCommands / Scripter

### `manual_validation_required` status

**Cause:** MIDIKeyCommands and Scripter channels write MIDI to Logic Pro, but the server can't programmatically verify that Logic Pro's Key Commands assignments or Scripter MIDI FX are active. You must approve them explicitly.

**Fix:**
1. Complete the manual setup (Key Commands MIDI Learn, or Scripter script load).
2. Approve the channel:

```bash
LogicProMCP --approve-channel MIDIKeyCommands
LogicProMCP --approve-channel Scripter
LogicProMCP --list-approvals
```

3. Restart the MCP server so the router picks up the new approvals.

### Key Commands don't trigger in Logic Pro

**Cause (Logic 12.2+):** the `.plist` Key Commands import is **not supported** on Logic Pro 12.2. The `Logic Pro → Key Commands → Import…` menu item is grayed out — Logic 12 expects a different binary schema (`.logikcs`) and silently ignores legacy plist imports. This was historically misleading in our docs; if you followed a pre-v3.1.6 SETUP guide expecting the import to "just work", you would have been stuck here.

**Migration (pre-v3.1.6 users):**

1. Don't try to `Import…` the `.plist`. Treat the `Scripts/keycmd-preset.plist` file purely as a **CC→Command mapping reference**.
2. Most Key Commands ops are now routed via the regular tools (`logic_edit`, `logic_project`, `logic_navigate`, `logic_tracks`, `logic_transport`) without any binding — see `docs/SETUP.md §4.1` for the audited coverage matrix.
3. Bind only the channel-only ops you actually need (e.g. `transport.capture_recording`) via manual MIDI Learn — see `docs/SETUP.md §4.2` for a step-by-step walkthrough.

**Fix (per binding, ~2 minutes):**

1. Open **Logic Pro → Key Commands → Edit** (`⌥K`).
2. Search for the target command (e.g. "Capture Recording").
3. Click **Learn New Assignment**.
4. Send the matching CC on Channel 16 from your MCP client using `port:"keycmd"`:
   ```jsonc
   logic_midi.send_cc { "controller": 73, "value": 127, "channel": 16, "port": "keycmd" }
   ```
5. Click **Save Assignments**.

If nothing happens during Learn capture: confirm the keycmd port is approved (`LogicProMCP --approve-channel MIDIKeyCommands`) and that `LogicProMCP-KeyCmd-Internal` is selected as a MIDI input in Logic's Project Settings → MIDI → Inputs.

---

## AppleScript / Project Lifecycle

### `project.open` returns "Failed to verify opened project"

**Cause:** Logic Pro opened the file but is stuck on a save/migrate/chooser dialog.

**Fix:**
1. Bring Logic Pro to the front and dismiss any dialogs.
2. Retry `project.open`. The server auto-retries once after closing any front document.

### `project.open` rejects a valid path

**Cause:** Path validation (`AppleScriptSafety.isValidProjectPath`) enforces:
- Absolute path (starts with `/`)
- `.logicx` extension (case-sensitive on some filesystems)
- No control characters
- Not under `/dev/`
- Directory exists with `Resources/ProjectInformation.plist` and `Alternatives/*/ProjectData`

**Fix:** Verify the path is a genuine Logic Pro project package:

```bash
ls "/path/to/project.logicx/Resources/ProjectInformation.plist"  # must exist
ls "/path/to/project.logicx/Alternatives"/*/ProjectData           # must exist
```

### `project.save_as` fails silently

**Cause:** Logic Pro's Save As dialog didn't appear (window focus issue).

**Fix:**
1. Bring Logic Pro to front: `osascript -e 'tell application "Logic Pro" to activate'`
2. Retry.

---

## State & Caching

### `transport.get_state` returns empty or stale data

**Cause:** No project is open, or MCU hasn't completed handshake.

**Check:**
```
logic_system health → mcu.connected, cache.transport_age_sec
```

- `cache.transport_age_sec > 10` and MCU disconnected → AX poll is the only source.
- `cache.transport_age_sec > 60` → poller may have stopped. Run `logic_system refresh_cache`.

### Track list doesn't update after creating a new track

**Cause:** AX polling runs every 5s. The cache may not have refreshed yet.

**Fix:**
```
logic_system refresh_cache
```

Or wait up to 5 seconds.

### `logic://markers` returns empty `[]` even though the project has markers (Logic 12.2+)

**Cause:** v3.1.9 reads markers from the dedicated **Marker List** window's AX table. On Logic Pro 12.2+ user markers are *not* present in the main arrange window's AX subtree at all — Apple removed the role in 12.2 (verified `osascript`: zero `AXRuler` elements in arrange window). The fix landed in v3.1.9 but requires that window to be open.

**Symptom:**
```json
GET logic://markers
{ "source": "ax_live", "data": [], "ax_occluded": false }
```

`source: "ax_live"` (not `"default"`) means the v3.1.9 walker ran successfully — it just couldn't locate the marker list window because it's closed.

**Fix:** open the Marker List window once via `탐색 → 마커 목록 열기` (KR) / `Navigate → Open Marker List` (EN). You can minimise it after; the AX walk still finds it as long as it's open. After ~3-15 seconds the next poll cycle picks up the markers.

You can verify the window is recognised with:
```bash
osascript -e 'tell application "System Events" to tell process "Logic Pro" to return name of windows'
# expect at least one entry ending in "- 마커 목록" (KR) or "- Marker List" (EN)
```

The Marker List window stays open across project saves but **closes when you close the project**, so the workflow is "open project → open marker list → leave it open for the session." If you regularly need fresh marker reads, leave it docked / minimised; CPU cost is negligible.

This is an explicit UX trade-off vs auto-opening the window. If your workflow needs a hands-off path, an env-gated auto-open (`LOGIC_PRO_MCP_AUTO_OPEN_MARKER_LIST=1`) can ship in a future patch — file an issue.

### `logic://markers` works on Logic 12.0/12.1 but not on 12.2 (or vice versa)

The v3.1.9 walker has three strategies in this order:
1. **Marker List window AXTable** (Logic 12.2+ canonical surface — required on 12.2)
2. **AXRuler structural position** (Logic 11.x / earlier 12.x)
3. **Keyword identifier match** (`marker` / `마커` — Logic 10.x)

If markers work on one Logic version and not another, check `source` in the envelope:
- `"source": "ax_live"` + non-empty data → all good
- `"source": "ax_live"` + empty data → walker ran, found no markers (project may genuinely have none, OR marker list window is closed on 12.2)
- `"source": "default"` → poller hasn't populated yet (cold-start) — wait 3-15s for the next poll cycle
- `"source": "cache"` + `ax_occluded: true` → plugin window or modal stole AX focus from arrange; previous values served

For a fresh diagnosis dump, restart the MCP server with `LOG_LEVEL=debug` and grep for `[poller]` lines — every marker poll cycle logs success/failure detail.

### `logic://project/info` shows `tempo: 120, trackCount: 0` (defaults) even with a real project open

**Cause:** Likely running v3.1.7 or older. v3.1.8 introduced project-file (`MetaData.plist`) tier-merge; before that, the AX path only filled `name` and left tempo/timesig/trackCount at struct defaults.

**Fix:** `brew upgrade logic-pro-mcp` to v3.1.8+. Verify via `serverInfo.version` after `tools/list` — it should show 3.1.8 or newer. If you can't upgrade, restart Logic with the project saved (the AppleScript-primary path that v3.1.5 introduced was always-failing on 12.x and has been removed in v3.1.8).

---

## Performance

### Tool calls take >3 seconds

**Likely cause:** AX-based reads (tracks, mixer) on a large project (100+ tracks).

**Mitigations:**
- Use `logic_system health` to confirm MCU is connected — MCU reads are <10ms vs 500ms+ for AX.
- Keep only the tracks you need visible in the Logic Pro arrange view — AX scans visible elements.
- Check `health.cache.poll_mode`: `"active"` means recent tool access, polling adaptive; `"idle"` uses longer intervals.

### Memory grows over time

**Expected:** 40–70 MB baseline, <100 MB after heavy use.

If memory exceeds 200 MB:
1. Capture `health` output.
2. Restart the MCP server.
3. File a bug with `health` JSON + stderr log.

---

## Logging

### Enable DEBUG log

```bash
# For Claude Code integration, set the env var in Claude's config.
# For manual testing:
LOG_LEVEL=DEBUG LogicProMCP 2>/tmp/mcp-debug.log
```

Subsystems:
- `server`, `router`, `main` — lifecycle
- `mcu`, `midi`, `keycmd`, `scripter` — MIDI path
- `ax`, `poller` — Accessibility
- `cgEvent`, `appleScript` — fallback channels

### Finding errors in logs

```bash
grep -iE "error|warn|fail" /tmp/mcp-debug.log
```

### Capture a full debug session

```bash
LOG_LEVEL=DEBUG python3 scripts/live-e2e-test.py 2>/tmp/mcp-session.log
```

---

## Logic Pro crashes during UI automation

**Observed:** `EXC_BAD_ACCESS at 0x2d0` during rapid AppleScript UI scripting of Logic Pro 12.0.1 (build 6590, macOS 26.3).

**Cause:** Logic Pro's file-import dialog has a race condition under rapid keystroke/menu automation. Firing `⌘⇧G → path → Return → Return` in sub-second succession triggers a null-pointer deref inside Logic Pro.

**Workaround:** **Do not automate Logic Pro's Import Audio File dialog.** The MCP server does not expose an `audio.import` operation for this reason — it cannot be done safely through UI scripting.

**Instead:**
1. Use the MCP server for what it reliably handles: transport, track create/rename, tempo, MCU mixer, MIDI I/O.
2. For audio file imports, open the stems folder in Finder (`open -R /path/to/folder`) and drag files into Logic Pro manually. Logic handles native drag-drop robustly.
3. See `scripts/analysis-to-logic.py` for the reference pattern: it does tempo + track setup via MCP and opens Finder for the user to drag.

**If Logic Pro crashed:**
- Crash dumps are in `~/Library/Logs/DiagnosticReports/Logic Pro-*.ips`
- Reopen Logic; the project chooser appears
- Any uncommitted work prior to the crash is lost unless Autosave captured it (`Preferences → General → Autosave`)

---

## Emergency Recovery

### Unresponsive server

```bash
# Force-kill
pkill -9 LogicProMCP

# Restart via Claude Code (toggle MCP connection off/on)
# Or run manually
LogicProMCP --check-permissions
```

### Corrupted approval store

```bash
rm ~/Library/Application\ Support/LogicProMCP/operator-approvals.json
LogicProMCP --list-approvals   # should report empty
# Re-approve as needed
LogicProMCP --approve-channel MIDIKeyCommands
LogicProMCP --approve-channel Scripter
```

### Virtual MIDI ports stuck after crash

```bash
# List MIDI clients
system_profiler SPMidiDataType | grep -A 2 LogicProMCP

# Restart CoreMIDI server (nuclear option)
sudo launchctl kickstart -k system/com.apple.audio.coreaudiod
```

Virtual MIDI ports registered by crashed processes usually disappear within 30 seconds; if they persist, restarting the system audio daemon clears them.

---

## Getting Help

1. Run `LogicProMCP --check-permissions` — paste output.
2. Capture `logic_system health` JSON.
3. Capture last 100 lines of `LOG_LEVEL=DEBUG` stderr.
4. File an issue with:
   - macOS version (`sw_vers`)
   - Logic Pro version
   - Server version (`LogicProMCP --version` if available, or the release tag)
   - The three captures above
