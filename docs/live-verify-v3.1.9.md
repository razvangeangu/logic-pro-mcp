# Live Verification Runbook — v3.1.9 (Logic Pro 12.2 markers)

This runbook captures the **manual + automated verification matrix** used to ship v3.1.9 (Issue #8 follow-up to v3.1.8 #7 fix). Use it after every release that touches `enumerateMarkers`, `LogicProjectFileReader`, `ResourceHandlers.readMarkers/readTracks/readProjectInfo`, or the `StateCache.update*` invariants.

The runbook splits into three tiers:
1. **Automated** — runs without Logic Pro state assumptions; CI-friendly
2. **Live e2e** — needs a running Logic Pro 12.x with a known project
3. **Honest disclosure** — what was *not* tested and why

---

## Tier 1 — Automated (runs in `swift test --no-parallel`)

### 1057-test baseline (post v3.1.9)

```bash
swift test --no-parallel
# → 1059 / 1059 PASS in ~22s
```

If this drops below 1059, regression. If a new test is added without bumping this baseline, document the increment in CHANGELOG.

### Targeted v3.1.9 regression suite

```bash
swift test --no-parallel --filter "AXMarkers12MarkerListTests"
# → 12 / 12 PASS

swift test --no-parallel --filter "LogicProjectFileReaderTests"
# → 15 / 15 PASS

swift test --no-parallel --filter "Issue7IntegrationTests|Issue7BackwardCompat"
# → 10 / 10 PASS

swift test --no-parallel --filter "ResourceProjectInfoTierMerge|ResourceTracksTierMerge|ResourceEnvelopeExtras"
# → 24 / 24 PASS
```

Each suite isolates a single fix axis: AX walker locale matrix, plist parsing, integration scenarios, resource handler tier merges.

### Build hygiene

```bash
swift build -c release
# → Build complete! No warnings.
```

Should emit zero `warning:` lines (excluding macOS-specific deprecation notices outside our code).

### `brew test`

```bash
brew test logic-pro-mcp
# → Testing monglong0214/logic-pro-mcp/logic-pro-mcp
# → /opt/homebrew/Cellar/logic-pro-mcp/<v>/bin/LogicProMCP --check-permissions
# → exit=0 (granted) or exit=1 (missing) — both acceptable
```

If formula version doesn't match `Sources/LogicProMCP/Server/ServerConfig.swift::serverVersion`, the `testServerVersionMatchesPackagingArtefacts` Swift test will fail and `git push origin v<tag>` will reject — `Scripts/release.sh` enforces this pre-tag.

---

## Tier 2 — Live e2e (Logic Pro 12.2 required)

### 2.1 Project file metadata path (#4 ↪ v3.1.8)

**Setup**: Open `Lofi-Dreamscape-80.logicx` (BPM 80, 31 tracks, 4/4) in Logic. Focus the Tracks (arrange) panel.

```bash
cat <<'EOF' > /tmp/probe.json
{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"probe","version":"1"}}}
{"jsonrpc":"2.0","method":"notifications/initialized"}
{"jsonrpc":"2.0","id":2,"method":"resources/read","params":{"uri":"logic://project/info"}}
EOF
cat /tmp/probe.json | LogicProMCP 2>/dev/null | python3 -c "
import json, sys
for line in sys.stdin:
    if not line.strip(): continue
    d = json.loads(line)
    if d.get('id') == 2:
        text = d['result']['contents'][0]['text']
        env = json.loads(text)
        data = env['data']
        print('source:', env.get('source'))
        print('tempo:', data.get('tempo'), 'timesig:', data.get('timeSignature'), 'trackCount:', data.get('trackCount'))
"
```

**Expected**:
```
source: project_file (or ax_live if poller has populated cache with non-default values)
tempo: 80
timesig: 4/4
trackCount: 31
```

**Fail conditions**:
- `tempo: 120 timesig: 4/4 trackCount: 0` → struct defaults; v3.1.8 file-tier merge isn't running. Likely an older binary; check `serverInfo.version`.
- `source: default` and Logic IS running → `LogicProjectFileReader` couldn't locate `MetaData.plist`; check the `path of front document` AppleScript term works (`osascript -e 'tell application "Logic Pro" to return path of front document'`).

### 2.2 Track Inspector contamination guard (#3 ↪ v3.1.8)

**Setup**: Same Lofi project. Toggle the Mixer panel via `보기 → 믹서` (or Cmd+2). The mixer takes focus over the arrange.

```bash
# Same probe.json as 2.1 but for tracks instead
{"jsonrpc":"2.0","id":3,"method":"resources/read","params":{"uri":"logic://tracks"}}
```

**Expected**:
- `source: ax_live_with_file_count` (cache empty + file count 31) **OR** `source: ax_live` (live AX still resolved real names because arrange wasn't fully obscured)
- All entries should have `placeholder: true` if `ax_live_with_file_count`, else `placeholder: false` with real instrument names
- **Critical**: zero rows with names ending in `:` (e.g. `Mute:`, `Loop:`, `Quantize:` — that's the v3.1.4 Inspector subtree leak)

**Fail condition**: any entry with `name` ending in `:` and a count of 12+ such rows → Inspector contamination guard failed. Check `AXLogicProElements.getTrackHeaders` line 325-330.

### 2.3 Marker walker on Logic 12.2 (#5 ↪ v3.1.9)

**Setup**: Project with 5+ named markers; **Marker List window must be open** (`탐색 → 마커 목록 열기` / `Navigate → Open Marker List`).

```bash
# Add to probe.json:
{"jsonrpc":"2.0","id":4,"method":"resources/read","params":{"uri":"logic://markers"}}
# Sleep 8 seconds before this read so the poller has a chance to scrape.
```

**Expected** (project with markers at bars 1, 5, 17):
```json
{
  "source": "ax_live",
  "data": [
    {"id": 0, "name": "Intro", "position": "1.1.1.1"},
    {"id": 1, "name": "Verse", "position": "5.1.1.1"},
    {"id": 2, "name": "Chorus", "position": "17.1.1.1"}
  ]
}
```

**Fail conditions**:
- `source: default, data: []` → Walker didn't run OR marker list window isn't open. Check `osascript -e 'tell application "System Events" to tell process "Logic Pro" to return name of windows'` includes `<project> - 마커 목록` (KR) or `<project> - Marker List` (EN).
- `source: ax_live, data: []` on a project with markers → Walker ran but found zero. Check the marker list window's AXTable structure manually via Accessibility Inspector — Apple may have changed the cell hierarchy.
- Non-empty `data` but `name` looks wrong (placeholders, garbled unicode) → Korean/locale path. Check `markerCellPlaceholders` set in `AXLogicProElements`.

### 2.4 Marker mutation cache consistency

**Setup**: Same project, marker list window open, MCP server running with cache populated.

1. Note current marker count: `osascript -e 'tell application "System Events" to tell process "Logic Pro" to return value of every static text whose description is "항목 수" of front window'`
2. Delete one marker via UI: select first row, press Delete
3. Re-read `logic://markers` after 4 seconds (one poll cycle).

**Expected**: count drops by exactly 1.

### 2.5 Minimised marker list workflow (production UX)

**Setup**: Marker list open with 5+ markers.

1. Click marker list window to focus
2. Press Cmd+M (minimise window to dock)
3. Verify both windows still listed in `kAXWindowsAttribute`:
   ```bash
   osascript -e 'tell application "System Events" to tell process "Logic Pro" to return name of windows'
   ```
4. Re-read `logic://markers`.

**Expected**: `source: ax_live`, all markers still surface.

This validates the recommended production workflow ("open marker list once, minimise, work in arrange").

### 2.6 Closed marker list — honest empty signal

**Setup**: Close marker list window via Cmd+W or click the close button.

```bash
# Re-read logic://markers after 8s for a poll cycle
```

**Expected**:
- `source: ax_live` (post-v3.1.9 cache invariant fix)
- `data: []`
- `cache_age_sec` is a small number (a recent successful poll observed empty)

**Fail condition**: `source: default` → the v3.1.9 `StateCache.updateMarkers` invariant fix hasn't landed; check `markersFetchedAt` is being unconditionally advanced.

### 2.7 Both Logic windows minimised — poller backs off

**Setup**: Cmd+M each Logic window until none are visible.

**Expected**: `logic://markers` returns `source: default, data: []` after 9+ seconds (consecutiveWindowMisses ≥ failureThreshold). The poller intentionally stops when `hasVisibleWindow()` returns false to conserve CPU.

Restoring the arrange window resumes polling within 3-5 seconds.

---

## Tier 3 — Honest disclosure (out of scope / NOT tested)

### Not tested in v3.1.9

- **Logic Pro 12.3+** — not yet released as of 2026-05-07. Marker list AX hierarchy may shift. Add to runbook when a 12.3 install is available.
- **Logic Pro 11.x** — the v3.1.9 `enumerateMarkers` Strategy 2 (`AXRuler` walk) was preserved for back-compat but only via synthetic AX tree tests, not against a real 11.x install on this dev box.
- **Other locales beyond {KR, EN}** in live UI — synthetic test fixtures cover 13 locales (`markerListWindowSuffixes`), but no live verification on JP/FR/DE/ES/IT/ZH-S/ZH-T/RU/PT/NL.
- **AX permission revocation mid-session** — kill+restart MCP works, but live revocation via System Settings while MCP is mid-poll is not exercised.
- **Plugin window AX occlusion** — `ax_occluded: true` propagation tested via unit tests with synthetic dialog elements; not verified end-to-end with a real Logic plugin window.
- **Track names via project file (NG1)** — `Alternatives/000/ProjectData` is a binary blob; reverse-engineering deferred. The placeholder rows path (`name: "Track \(i)"`, `placeholder: true`) is the documented honest fallback.
- **Marker positions / names from project file (NG2)** — same as NG1.
- **Per-section document-identity contract (NG8)** — when a user switches between two open projects, the cache section may briefly contain stale data from the previous project. Existing `hasDocument: false` invalidation handles project close, but rapid project-switch race is theoretically possible. No live repro on this dev box.
- **Tri-state marker result (NG9)** — `ax_occluded: true` is the existing untrusted-empty signal; no separate `unreadable` state. Acceptable per PRD.

### Auto-open Marker List (post-v3.1.9 enhancement candidate)

Currently the user must manually open the Marker List window. An env-gated auto-open is sketched in TROUBLESHOOTING.md (`LOGIC_PRO_MCP_AUTO_OPEN_MARKER_LIST=1`) but not implemented. Open an issue if you'd like it shipped.

---

## When to update this runbook

- Any change to `AXLogicProElements.enumerateMarkers*`, `findMarkerListWindow*`, or marker walker strategy ordering
- New locale added to `markerListWindowSuffixes` or `markerCellPlaceholders` → add a Tier 2 live check on a sample of the new locale
- `StateCache.update*` invariant changes (advance fetchedAt vs not) → add corresponding Tier 1 regression test
- New Logic Pro major version (12.3+, 13+) → re-run all Tier 2 entries on a fresh install, document deltas

This runbook is **complementary** to the unit + integration test suite — they catch the deterministic regressions; this runbook catches the AX surface drift that no unit test can predict.
