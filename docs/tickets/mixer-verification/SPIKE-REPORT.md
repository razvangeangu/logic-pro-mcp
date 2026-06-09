# T0 Live Spike Report — Logic Pro 12.2 (2026-06-08)

> 2026-06-09 follow-up: the initial blocker in this report has been resolved. A later AX-tree dump found the Logic 12.2 mixer as `AXGroup desc=믹서` → `AXLayoutArea desc=믹서` → `AXLayoutItem` channel strips, excluding the inspector mixer. The implementation now uses that matcher plus description-based fader/pan/insert-slot discovery.

> E1 deliverable. Run against the live, connected MCP server (older build, pre-rc5 envelope) on Logic Pro 12.2, scratch project (8 tracks: Roland TR-909, Modern 909, …). Method: connected `mcp__logic-pro__*` tools + `logic://*` resource reads. (A standalone AX probe / new-binary run was NOT possible: the installed server owns the MCU/Scripter/KeyCmd virtual ports, and a freshly-built binary cannot obtain Accessibility (TCC) grants without the operator present.)

## Findings

### F-1 — #10 echo: CONFIRMED real-regression (live)
`logic_mixer set_volume {track:0, value:0.4}` → `{success:true, verified:false, reason:"echo_timeout_500ms", observed:null, track:0}`. Host-initiated fader write receives **no MCU echo** on Logic 12.2 (general MCU feedback IS flowing — strips carry connect-time-synced values — so this is the "connected + fresh, but this specific host-write echo never lands" shape, not a setup gap). Matches thomas-doesburg's probe conclusions exactly.

### F-2 — volume scale = normalized 0.0–1.0 (NOT dB)  ✅ resolves a key F1 unknown
Live `logic://mixer` strips: volume `0.7751`, `0.7888`, `0.7966`, `0.7986` — Logic's unity (0 dB) fader sits ≈ **0.785** in normalized fader units. The cached/echoed value is already 0–1, matching the `set_volume` write contract. **No dB↔normalized conversion is needed** for an AX-or-MCU-derived readback. (PRD's "AXSlider scale unknown / extractSliderRange normalization" risk is retired for volume.)

### F-3 — AX mixer read (`getMixerArea`) is BROKEN on Logic 12.2  ⛔ blocks F2/F3/G
Decisive isolation:
- `logic://tracks` → `source:"ax_live"`, `cache_age_sec:4.4` — **the AX poller works** (reads track headers fine).
- `logic://mixer` → `cache_age_sec:null`, `fetched_at:null` in **both** mixer-toggle states after a 5s poll cycle — **the mixer AX poll never populates the cache.** Its strip values come solely from MCU connect-time sync, not AX.

`AXLogicProElements.getMixerArea` (current code, AXLogicProElements.swift:491-500) locates the mixer by `findDescendant(role: AXGroup|AXScrollArea, identifier: "Mixer")`. On Logic 12.2 that identifier does not match the mixer pane → the AX fader/pan read path is dead, which is the underlying reason the mixer cache is MCU-echo-only. `findFader`/`findPanKnob` (positional slider[0]=volume / slider[1]=pan) are downstream of this and untestable live until `getMixerArea` resolves.

### F-4 — #11 readback: CONFIRMED stale (live)
After the `set_volume {track:0, value:0.4}` write, a re-read of `logic://mixer` still shows track 0 `volume:0` (unchanged). With no echo and a broken AX mixer read, the cache cannot reflect the post-write value. Single shared root cause with #10.

### F-5 — #12 plugins[]: CONFIRMED empty (live)
Every strip carries `plugins:[]`. Populating it needs (a) working mixer AX access (broken — F-3) for insert-slot enumeration, and (b) greenfield plugin-window parameter AX. Both blocked.

### F-6 — pan reliability uncertain
Strips show `pan:-1` for tracks 2–3, `0` elsewhere. Either genuinely panned or a positional `findPanKnob` (slider[1]) misread. Pan AX needs AXDescription-based matching, itself gated on F-3.

### F-7 — version/timestamp drift: CONFIRMED live
Every resource annotation reports `lastModified:"2026-04-19T00:00:00Z"` (the hardcoded `ResourceProvider.versionReleaseTimestamp`). Confirms C1's drift target.

## Scope decision (locked)

| Tier | Items | Disposition |
|---|---|---|
| **T1 (deterministic)** | A1 MCU_TRACE, A2/A3 (adopted), A4 set_pan disclosure, B1/B2 provenance, H1 MIDIEngine restart, H2 AX coord fallback, D1/D2 test hygiene, C2 docs, C1 version | **DELIVER** (no live AX needed; verified by tests) |
| **T2/T3 (AX-dependent)** | F2 AX independent volume/pan readback, F3 AX plugins[] snapshot, G1/G2/G3 opt-in insert_plugin / insert:N | **DELIVERED in 2026-06-09 follow-up** — `getMixerArea` restored for Logic 12.2, AX readback and insert-slot verification live-verified. |

## Follow-up implementation evidence (2026-06-09)

Targeted live E2E against the release binary on Logic Pro 12.2:

- #10: `set_volume {track:0,value:0.36}` returned `success:true`, `verified:true`, `verify_source:"ax_readback"`, `observed_ax:0.33777777777777773`, `observed_mcu:null`.
- #11: post-write `logic://mixer` returned `data_source:"ax_poll"` and track 0 `volume:0.33777777777777773`.
- #12: `plugins[]` populated from AX with `plugins_source:"ax"` and observed names `Gain`, `Gain`, `Gain`, `Drum Machine Designer` before the slot-4 insert.
- #13: `insert_plugin` requires L2 confirmation, inserted Gain verified by AX slot readback, and a repeat against the occupied slot failed closed with `slot_occupied`.

Regression gates:

- `swift test --no-parallel` → 1197 tests passed.
- `swift build -c release` → passed.

## Historical required follow-up spike (now complete)
1. Dump the Logic 12.2 mixer pane AX subtree (role + `AXIdentifier` + `AXDescription` at each level) to find the correct `getMixerArea` matcher (the `"Mixer"` identifier no longer matches). This single fix unblocks F2/F3/G.
2. With the mixer readable, characterize the fader vs pan vs send sliders by `AXDescription` (replace positional slider[0]/[1]) and confirm pan scale.
3. Dump a stock Channel EQ / Compressor plugin-window AX subtree to assess plugin-param readback feasibility (#12 / F3) and the blind-CC↔AX-slider mapping.
4. Dump a channel-strip insert-slot element (empty vs populated) for #13 / G insert flow.

## Alternative readback note

The file-based readback idea is no longer the only echo-independent route for Logic 12.2 fader verification because AX mixer readback is now restored. It remains a possible future hardening path for deeper `apply_moves` verification and full plugin parameter persistence checks, but it is not required for v3.4.5 #10/#11 closure.
