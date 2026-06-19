# Verified Plugin Apply-Back Guide

This guide covers the `logic_plugins` tool — the verified apply-back surface for Logic Pro stock plugin parameters.

**Audience:** Thomas apply_moves workflow and any caller that needs to read a plugin's insert state and write back a parameter value to a duplicate project.

---

## Overview

The verified apply-back surface is purpose-built for one use case: an LLM agent that has analyzed a **source** project and needs to reproduce the same plugin settings on a **duplicate** project. The `duplicate_applyback` mode is the only write mode in Release 1. It requires an explicit project path gate before any write touches the file.

Three commands cover the full workflow:

| Command | What it does |
|---------|-------------|
| `get_inventory` | Read the physical insert chain for a track. |
| `set_param_verified` | Write a parameter and confirm via readback. |
| `insert_verified` | Live, readback-verified plugin insert via the target slot's own popup menu. |

---

## Prerequisites

1. **Logic Pro is running** with the duplicate project as the front document.
2. **AX permissions granted** (`System Settings → Privacy & Security → Accessibility`).
3. For `set_param_verified`: **the target plugin window must already be open** in Logic Pro (see [Plugin window limitation](#limitation-1-plugin-window-must-already-be-open)).

---

## Step 1 — Read the insert inventory

Before writing any parameter, call `get_inventory` to obtain the physical insert index for the target plugin.

```json
{
  "name": "logic_plugins",
  "arguments": {
    "command": "get_inventory",
    "params": { "track": 5 }
  }
}
```

**Why `get_inventory` and not `logic://mixer`?**

`logic://mixer` exposes a legacy insert snapshot that may drift from the true AX slot positions. `get_inventory` reads the physical AX insert chain directly, preserving the exact slot indices that `set_param_verified` and `insert_verified` use. Always use the `insert` value from `get_inventory` — never the index from the mixer resource.

**Interpreting the response**

```json
{
  "success": true,
  "verified": true,
  "state": "A",
  "hc_schema": 2,
  "complete": true,
  "plugins": [
    {
      "insert": 6,
      "read_status": "ok",
      "occupied": true,
      "name": "Compressor",
      "plugin_id": "logic.stock.effect.compressor",
      "bypassed": false
    }
  ]
}
```

| Field | Meaning |
|-------|---------|
| `insert` | Physical 0-based slot index. Use this value when calling `set_param_verified` or `insert_verified`. |
| `read_status` | `"empty"` — unoccupied; `"ok"` — readable; `"unreadable"` — occupied but name cannot be read. |
| `occupied` | `true` when the slot has a plugin. |
| `name` | Plugin display name as reported by AX, or `null`. |
| `plugin_id` | Canonical `logic.stock.effect.*` ID, or `null` when the plugin is not an allowlisted stock plugin. |
| `bypassed` | Bypass state, or `null` when unreadable. |
| `complete` | `false` when any slot is `unreadable`. Do not proceed with a write when `complete` is `false`. |

**When `complete` is `false`:** one or more slots returned `read_status: "unreadable"`. The physical slot positions for those slots are unknown. Retry after Logic Pro has finished rendering or the mixer is fully visible. Never assume an `unreadable` slot is empty.

---

## Step 2 — Confirm `project_expected_path`

Every mutating `logic_plugins` command requires `project_expected_path`. This is the absolute path of the Logic project that must be the front document when the write executes.

Obtain the path before calling `set_param_verified`:

```json
{
  "name": "logic_project",
  "arguments": { "command": "is_running" }
}
```

Then read `logic://project/info` to confirm `filePath`.

The project path gate reads the live front document path via AppleScript at the moment of the call and rejects the request when it does not match `project_expected_path`. This prevents writes from landing on the wrong file when a user switches projects between plan and execute.

---

## Step 3 — Write a parameter (set_param_verified)

Once you have the `insert` index and `project_expected_path`, write the parameter:

```json
{
  "name": "logic_plugins",
  "arguments": {
    "command": "set_param_verified",
    "params": {
      "track": 5,
      "insert": 6,
      "plugin": "compressor",
      "param": "threshold",
      "value": 60,
      "mode": "duplicate_applyback",
      "project_expected_path": "/Users/isaac/Music/acid-track-applyback-test.logicx"
    }
  }
}
```

---

## Interpreting State A / B / C

Every `logic_plugins.*` response carries `state`, `hc_schema: 2`, and (for State C) `verified: false`.

### State A — confirmed write

```json
{
  "success": true,
  "verified": true,
  "state": "A",
  "hc_schema": 2,
  "operation": "logic_plugins.set_param_verified",
  "param": "threshold",
  "requested_normalized": 60.0,
  "observed_normalized": 60.0,
  "observed_display": "60 %",
  "display_unit": "%",
  "tolerance": 1.0,
  "write_source": "ax_plugin_window",
  "verify_source": "ax_plugin_window"
}
```

`verified: true` means the write **landed and the readback confirmed it** within `tolerance`. This is the only State A outcome — `set_param_verified` never returns State A without a completed AX write + readback round-trip.

Key fields:

| Field | Meaning |
|-------|---------|
| `requested_normalized` | The value you sent. |
| `observed_normalized` | The value read back from the AX slider after the write. |
| `observed_display` | The `AXValueDescription` string (e.g. `"60 %"`). |
| `display_unit` | Always `"%"` for `threshold` — the AX display is normalized %, not dB. |
| `write_source` | Always `"ax_plugin_window"` — the write went through the open plugin window. |
| `verify_source` | Always `"ax_plugin_window"` — the readback came from the same window. |

### State B — uncertain (inventory read-unavailable)

`get_inventory` returns State B when the AX mixer subtree cannot be found at all (e.g. Logic is not running or the mixer is closed). `safe_to_retry: true` means opening the mixer and retrying is the correct action.

`set_param_verified` never returns State B — it either succeeds (State A) or fails (State C).

### State C — hard failure

```json
{
  "success": false,
  "verified": false,
  "state": "C",
  "hc_schema": 2,
  "error": "window_open_failed",
  "what_was_attempted": "...",
  "what_was_observed": "...",
  "safe_to_retry": true,
  "write_attempted": false
}
```

`write_attempted: false` means the parameter value in Logic Pro is unchanged. `write_attempted: true` means the write executed but could not be confirmed (readback failed or mismatched); rollback was attempted in that case.

**Decision table for `safe_to_retry`**

| `error` | `safe_to_retry` | Recommended action |
|---------|-----------------|---------------------|
| `window_open_failed` | `true` | Open the plugin window in Logic Pro, then retry. |
| `track_selection_failed` | `true` | Logic may be mid-animation; wait 200 ms and retry. |
| `incomplete_inventory` | `true` | Mixer not fully visible or Logic busy; retry after a pause. |
| `readback_lost_after_write` | `true` | Window may have closed during the write; reopen and retry. |
| `readback_mismatch` | `false` | The value did not land as expected; rollback attempted. Investigate before retrying. |
| `project_identity_mismatch` | `false` | The wrong project is in front. Bring the correct project forward. |
| `unsupported_param_readback` | `false` | This parameter has no verified write path. Use `logic_mixer.set_plugin_param` (legacy, unverified) or wait for a future release. |
| `unknown_plugin_identity` | `false` | Plugin alias not in the allowlist. Check the canonical ID table. |

---

## Targeting by physical index

`logic://mixer` and `get_inventory` may report different insert indices for the same slot. This is D1 drift: the mixer cache counts only occupied slots from the top, while the AX insert chain reports the true physical slot positions. Always use the `insert` value from `get_inventory`.

**Example:** a track has inserts at physical slots 0 (Channel EQ), 3 (empty), and 6 (Compressor). `logic://mixer` may report the Compressor at index `1` (second occupied slot); `get_inventory` reports it at `insert: 6`.

If you call `set_param_verified` with `insert: 1`, it will address slot 1 — which may be empty or hold a different plugin — and return State C `incomplete_inventory` or a plugin mismatch.

---

## Limitations

### Limitation 1 — Plugin window must already be open

`set_param_verified` can only write to a plugin window that is **already open** in Logic Pro. The AX approach to opening a plugin window by double-clicking the mixer insert slot is brittle because Logic virtualizes channel strip rendering (the mixer insert buttons are not reliably addressable by AX from outside Logic). The implementation falls back to a programmatic opener, but the production default is a no-op.

**Workaround:** open the plugin window manually in Logic Pro before calling `set_param_verified`. The command will find the open window by matching the track name and the presence of the target AX slider.

Programmatic window opening is a separate work item (T6). Until it ships, `window_open_failed` with `safe_to_retry: true` is the expected response when no window is open.

### Limitation 2 — Parameters are normalized %, not dB

Logic's AX interface does not expose the dB-mapped values for Compressor parameters. `AXValue` is a normalized 0–100 float; `AXValueDescription` is `"X %"`. The `observed_display` field in State A shows the AX-reported display string. There is no verified mapping from normalized % to the dB value shown in the Logic Pro UI.

For the Compressor `threshold`:

| Normalized value (request) | AX display | Logic UI dB display |
|---------------------------|------------|---------------------|
| 0 | "0 %" | (maximum compression) |
| 100 | "100 %" | (no compression) |
| 60 | "60 %" | (unknown dB equivalent via AX) |

If you need to target a specific dB value, measure the normalized equivalent by reading `get_inventory` (or a live `set_param_verified` round-trip) after setting the value manually in Logic Pro.

### Limitation 3 — Track reorder breaks stable targeting

The `track` parameter is a 0-based index into the **visible mixer strip order**. If tracks are reordered between planning a workflow and executing it, the same index will address a different track. There is no stable track ID in the current AX surface.

**Mitigation:** use `project_expected_path` to gate all writes. Always call `get_inventory` immediately before `set_param_verified` in the same session — do not cache inventory across project reloads or reorders.

### Limitation 4 — Only Compressor `threshold` is verified-writable

**라이브 E2E 검증 완료 (2026-06-14).** `set_param_verified` Compressor `threshold`는 Logic Pro 12.2 라이브 세션에서 State A `verified:true`가 확인됐다. Track 5 insert 6 Compressor에서 `requested_normalized 60 → observed_normalized 60, observed_display "60 %" ` (51→60→51 양방향), 독립 osascript readback으로 실제 AX write 입증. Evidence: `docs/spikes/compressor-t0-evidence.md`.

All other plugin parameters return State C `unsupported_param_readback` at the capability preflight step — no write is attempted. This is because other Compressor parameters (ratio, attack, release) have `AXDescription: "슬라이더"` (locale word for "slider") and cannot be identified by description alone.

Additional parameters will be promoted to `writeReadback` as evidence is gathered for each one.

---

## insert_verified

`insert_verified` performs a **live, readback-verified** plugin insert via the target insert slot's own popup menu. **Live-E2E verified (2026-06-17):** target slot CGEvent click → anchored popup verification → exact plugin leaf selection returned `verified: true` for track 6 insert 6 (`write_source: ax_exact_slot_popup`, `slot_popup_anchor_verified: true`, `observed_slot: 6`), with independent `get_inventory` readback confirming `logic.stock.effect.gain` mounted at the requested insert while the previous empty slot stayed empty.

Flow: pre-insert gates (mode → project path → identity → inventory complete → slot empty) → clean state (hide plug-in windows, close any stray "위치로 이동"/"Go to Position" dialog, raise the mixer window) → select and verify the target track → click the target slot's AX center with CGEvent → verify the resulting popup is spatially anchored to that slot → choose the stock plugin by exact leaf title from that anchored popup (direct/root item, popup search result, then recursive hover discovery) → diff the pre/post inventory to detect where the plugin landed. The production path does not depend on localized category names such as `Utility`. **State A is emitted only when the post-insert readback observes the requested plugin newly mounted at the requested slot** — the readback diff is the sole State A path, so a false verified insert is structurally impossible.

### Slot model

Use `get_inventory` immediately before insertion and pass the `insert` value it returns. Logic Pro 12.2 exposes a short bottom "Audio Plug-in" append stub in some strips; live E2E showed that clicking it does **not** insert into that physical row, so `get_inventory` filters it out and only exposes addressable insert rows.

For exposed empty rows, the exact-slot popup path preserves the target slot context by proving the popup is anchored before any plugin leaf is clicked. Known wrong-slot causes (phantom append rows, stale plugin/search dialogs, unverified track selection, unanchored popup menus, localized category lookup misses) are blocked before the write boundary. If an unknown Logic UI drift still places the plugin at a different slot, `insert_verified` does **not** confirm a slot it did not target — it fails closed with State C `insert_landed_at_different_slot`, reporting the actual `observed_slot`, and rolls the stray mount back (Undo, confirmed by readback; `rollback_succeeded` reflects whether removal was verified).

If a stray/wrong plugin appears and automatic cleanup cannot confirm removal, the operation stops immediately with State C `rollback_failed` instead of trying more fallback clicks. This rollback path is an emergency invariant guard, not part of the normal exact-slot path. If the anchored popup selection appears to commit but readback never confirms the requested mount, the operation returns State C `operation_timeout` rather than clicking stale UI.

```json
{
  "name": "logic_plugins",
  "arguments": {
    "command": "insert_verified",
    "params": {
      "track": 2,
      "insert": 6,
      "plugin": "gain",
      "mode": "duplicate_applyback",
      "project_expected_path": "/Users/isaac/Music/acid-track-applyback-test.logicx"
    }
  }
}
```

State C example (Logic placed it elsewhere):

```jsonc
{
  "success": false, "verified": false, "state": "C",
  "error": "insert_landed_at_different_slot",
  "observed_slot": 5,
  "rollback_attempted": true, "rollback_succeeded": true
  // requested insert 0, but readback observed Gain at slot 5 → rolled back
}
```

**Insertable allowlist:** `"gain"`, `"channel eq"` / `"channeleq"`, `"compressor"`. `"noise gate"` is in the identity allowlist but is not insertable (excluded from `insert_verified`).

---

## Full workflow example (apply-back Compressor threshold)

```jsonc
// 1. Confirm the duplicate project is front
//    → read logic://project/info, note filePath

// 2. Read the inventory for the target track
{
  "name": "logic_plugins",
  "arguments": {
    "command": "get_inventory",
    "params": { "track": 5 }
  }
}
// → find "Compressor" at insert: 6, plugin_id: "logic.stock.effect.compressor"
// → confirm complete: true

// 3. Open the Compressor plugin window in Logic Pro (manual step — the
//    set_param_verified window opener is nil in production; an already-open
//    plugin window is required for the parameter write/readback)

// 4. Write the parameter
{
  "name": "logic_plugins",
  "arguments": {
    "command": "set_param_verified",
    "params": {
      "track": 5,
      "insert": 6,
      "plugin": "compressor",
      "param": "threshold",
      "value": 60,
      "mode": "duplicate_applyback",
      "project_expected_path": "/Users/isaac/Music/acid-track-applyback-test.logicx"
    }
  }
}
// → State A: observed_normalized: 60.0, observed_display: "60 %"
```

---

## Reference: canonical plugin IDs

| Display name | Canonical ID | Insertable | `threshold` write |
|-------------|-------------|-----------|-------------------|
| Compressor | `logic.stock.effect.compressor` | yes | yes (normalized %) |
| Gain | `logic.stock.effect.gain` | yes | no (unsupported_param_readback) |
| Channel EQ | `logic.stock.effect.channel_eq` | yes | no |
| Noise Gate | `logic.stock.effect.noise_gate` | no (identity only) | no |
