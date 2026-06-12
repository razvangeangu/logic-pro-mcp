# Live Verification Runbook — v3.2.0 (Marker Provenance, NG10 Deferred)

> Historical record (2026-06-12 docs refresh): latest production-readiness and live E2E evidence is in `README.md`, `CHANGELOG.md`, and `docs/live-verify-v3.5.0.md`; this file remains preserved implementation context.

**Verification timing**: Immediately before v3.2.0 release + permanent T0 spike record.
**Scope**: Marker `position_source` provenance + `goto_marker` uncertainty surfacing.
**Honest Deferred**: NG10 (sub-bar navigation accuracy) — Logic 12.2 position dialog uses a 4-segment AXSlider structure; the v3.2.0 approach failed. Requires deep analysis of raw slider value mapping in v3.3.

---

## T0 Spike Results — Permanent Record (2026-05-07)

### Environment
- macOS 25.3.0 (Darwin)
- Logic Pro 12.2 Korean build
- Project "무제 20 - 트랙" 1 track / 1 region
- IME: system default (Korean input mode possible)

### S2 Scenario (Korean build + system IME)

```
1. transport.goto_position bar=1 → success requested 1.1.1.1
2. AppleScript: keystroke "146.4.4.240" + return → spike_sent
3. logic://transport/state read after 4 seconds → position: "129.1.1.1"
```

**FAIL** — target `146.4.4.240` not reached; navigated to different position `129.1.1.1`. All sub-bar components (beat/div/tick) reset to 1.

### S2 Verification — Simple 1-component attempt (`keystroke "146"`)

Same baseline, then attempted `keystroke "146"` only. Result was the same `position: "129.1.1.1"` — no playhead change (already at 129.1.1.1, dialog closed without effect).

→ **Dialog input itself is not processed by keystroke**. Possible interference from main window keyboard shortcuts.

### Dialog AX Structure enum (measured)

```
window "위치로 이동" (Go To Position)
  AXGroup desc=01:04:16:00.00          ← SMPTE "current" (HH:MM:SS:FF.SUB)
    AXSlider × 5 segments              raw value ~1.85E+8 (internal encoding)
  AXGroup desc=\t129\t1\t1\t1          ← bar.beat.div.tick "current"
    AXSlider × 4 segments              raw value ~2.27E+15
  AXGroup desc=01:04:16:00.00          ← SMPTE "new"
    AXSlider × 5 segments
  AXGroup desc=\t129\t1\t1\t1          ← bar.beat.div.tick "new" focused=true
    AXSlider × 4 segments              raw value ~2.27E+15 (per-segment raw representation)
  AXButton × 2                          ← OK / Cancel
  AXStaticText × 3                      ← "New:" "Current:" "Go To Position"
```

### Broken assumptions (basis for PRD §3.4)

| PRD v0.4 assumption | Measured result |
|---------------------|----------------|
| Dialog has a single text input | ❌ 4-segment AXSlider structure (bar/beat/div/tick are separate) |
| `keystroke "B.B.D.T"` delivers native 4-component input | ❌ Keystroke does not reach segments |
| Logic top-left Position display directly surfaces cache | ✅ `logic://transport/state` surfaces accurately |
| `gotoPositionViaDialog` AppleScript can automate dialog input | ✅ Opening the dialog works; input fails |

### AXSlider direct value set attempt

```applescript
set value of (item 1 of sliders) to 146  → ERROR: AppleEvent handler structure failure
```

Nested AppleScript expression limitations + raw slider values (1.85E+8 / 2.27E+15) vs displayed values (146/4/4/240) mapping not decoded. Analysis task for v3.3.

### Decision (v3.2.0 scope reduced)

- **NG10 (sub-bar nav accuracy)**: Honestly deferred to v3.3 PRD. Deep analysis of dialog AXSlider 4-segment raw value mapping required.
- **v3.2.0 ship scope**: Marker provenance only — `MarkerState.positionSource` enum + `logic://markers` envelope + `goto_marker` uncertainty extras.
- **Why ship at all**: External users (`thomas-doesburg` etc.) can now detect fallback markers → surfaces caller responsibility. Immediately useful to prevent recurrence of v3.1.5-7 false-positive cycle.

---

## Tier 1 — Automated (CI / dev box)

```bash
swift test --no-parallel
# → 1064 (v3.1.11 baseline) + 17 new = 1081 PASS

swift build -c release
# → 0 warnings

swift test --no-parallel --filter MarkerState
# → Codable round-trip + legacy snapshot decode (.unknown) PASS

swift test --no-parallel --filter testServerVersionMatchesPackagingArtefacts
# → version 3.2.0 all artifacts synchronized and verified

brew test logic-pro-mcp
# → exit 0
```

## Tier 2 — Live (Logic Pro 12.2 real device)

### 2.1 Marker provenance — `logic://markers` envelope

```bash
# 1. Open Logic Pro Marker List window + add 1 marker
# 2. Edit the position in Marker List to an abnormal value (e.g., "abc") — to induce parser failure
# 3. logic_system refresh_cache
# 4. logic://markers read
```

Expected:
- Normal marker: `{"position": "1.1.1.1", "position_source": "parser", "is_canonical": true}`
- Parser-fail marker: `{"position": "1.1.1.1", "position_source": "fallback", "is_canonical": false}`

### 2.2 `goto_marker` uncertainty surfacing

`goto_marker { name: "[fallback marker name]" }` → response extras include `marker_position_uncertain: true` + `marker_position_source: "fallback"`.

When calling with a normal (parser) marker, uncertainty extras are absent — existing response unchanged.

### 2.3 Codable backward compat

v3.1.x JSON snapshot (e.g., `StatePoller.swift:272` decode path or `logic://markers` response saved by an external client) → marker `positionSource` missing → decoded as `.unknown` → `is_canonical: false`. Zero crashes. Unit test `markerState_codableLegacySnapshot_*` provides regression protection.

---

## Tier 3 — NG / Honest Disclosure

| NG | Content |
|----|---------|
| **NG10** | **Sub-bar navigation accuracy not closed in v3.2.0**. `goto_marker { name: "VOCALS" }` accurately surfaces the cache value `"146.4.4.240"`, but the AX channel navigates only the first dot-component (bar 146). Same behavior as v3.1.11. v3.3 PRD will attempt closure after analyzing dialog AXSlider 4-segment raw value mapping. |
| NG-v32-1 | Logic 11.x AX surface unverified — 12.x is primary |
| NG-v32-2 | Timecode precision nav requires separate `mmc.locate` (no automatic routing added in v3.2) |
| NG-v32-3 | Provenance `.unknown` case — only occurs from legacy cache snapshots. New markers always have an explicit `.parser` / `.fallback` |

---

## When to update this runbook

- When v3.3 attempts NG10 closure — add slider raw value mapping results
- When a new locale is reported — add a row to the Tier 2.1 table
- When Logic 13/14 is released — re-run entirely
