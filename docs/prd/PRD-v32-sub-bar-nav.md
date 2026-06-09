# PRD — v3.2 Sub-Bar Navigation (NG10) + Marker Provenance (Boomer P2-3)

> Historical record (2026-06-09 docs refresh): latest production-readiness and live E2E evidence is in `README.md`, `CHANGELOG.md`, and `docs/live-verify-v3.4.6.md`; this file remains preserved implementation context.

**Status**: Draft (v0.4 — boomer round 3 P1+P2 integrated)
**Size**: L
**Owner**: Isaac
**Started**: 2026-05-07
**Driving issues**:
- v3.1.11 NG10 (Guardian P0-1) — `gotoPositionViaBarSlider` consumes only the first dot-component
- v3.1.11 Boomer P2-3 — Marker fallback position (`\(index+1).1.1.1`) has no machine-readable provenance

---

## 1. Goal

Make `goto_marker { name: "VOCALS" }` **actually** reach the precise `"146.4.4.240"` stored in the cache. v3.1.11 scoped only to cache accuracy. v3.2 closes the loop with navigation accuracy.

Additionally, surface whether a marker `position` field came from parser success or fallback in a machine-readable form — so callers can detect fallback positions before `goto_marker` routes to them.

## 2. Non-Goals

- Logic 11.x AX surface — out of scope (12.x primary). 11.x is a follow-up.
- Timecode (HH:MM:SS:FF) sub-frame nav — separate PRD (CoreMIDI MMC scope).
- Changes to the existing parser — v3.1.11 strict 4-component policy preserved. v3.2 changes **caller side only**.
- Full-precision empty-project navigation — Logic dialog is disabled. Slider fallback handles partial (bar+beat).

## 3. Background

### 3.1 v3.1.11 endpoint (cache accuracy)

```
logic://markers → MarkerState{ id, name, position: "146.4.4.240" }
```

`position` comes from two paths:
1. **Parser success**: `parseMarkerListPosition("146 4 4 240.")` → `"146.4.4.240"` (canonical)
2. **Parser fallback**: returns `nil` → caller uses `\(index+1).1.1.1` (manufactured but honest)

Callers cannot distinguish the two → when `goto_marker` routes to a fallback position, it silently navigates to the wrong bar.

### 3.2 v3.1.11 nav limitation (NG10)

```swift
// Sources/LogicProMCP/Channels/AccessibilityChannel.swift:2206-2208
let parts = pos.split(separator: ".")
if let first = parts.first, let b = Int(first) {
    targetBar = b
}
```

With input `"146.4.4.240"`, only `targetBar = 146` is set. beat=4, div=4, tick=240 are ignored. The slider path sets only the bar slider and resets beat slider to 1 (whole-bar intent).

### 3.3 Current TransportDispatcher validation (code-verified)

`Sources/LogicProMCP/Dispatchers/TransportDispatcher.swift:150` `isValidPositionString` — accepts exactly 4-component bar.beat.sub.tick (bar 1..9999, beat 1..16, sub 1..16, tick 1..999) **or** SMPTE only. 1-component `"146"` is rejected. Integer `bar` input is handled by a separate branch (line 90).

→ **PRD v0.2 correction**: Removed 1-component back-compat AC. The existing dispatcher already rejects it — retain that rejection.

### 3.4 Logic 12.2 dialog behavior (T0 spike — verification gate)

Whether the `탐색 → 이동 → 위치…` (`Navigate → Go To → Position…`) dialog accepts `bar.beat.div.tick` 4-component text input is **itself unverified**.

**P0 (Boomer)**: Implementation must not begin based on this assumption. **T0 live spike is the release gate**.

T0 spike procedure (required before implementation):
1. Empty project + 1 region → manually open `탐색 → 이동 → 위치…` (`Navigate → Go To → Position…`)
2. Attempt keystroke `"146.4.4.240"` + return in 3 scenarios: Korean IME ON / English build / English build + Korean IME
3. Visually confirm in each that the playhead reaches the precise sub-bar (bar 146 / beat 4 / div 4 / tick 240) + check Logic's top-left Position display
4. **Proceed with v3.2 implementation only if all 3 scenarios PASS**. If any FAIL → strengthen IME mitigation (P1-1) or reduce nav scope

### 3.5 IME mitigation (P1-1 strengthened)

AppleScript `keystroke "."` may drop ASCII punctuation in Korean IME Hangul mode. Simple `keystroke` splitting uses the same input source path → no effect (Boomer is correct).

**3-tier mitigation** (v0.3 — Tier 3 clarified):
1. **Tier 1 (preferred)**: Pasteboard paste — set `"146.4.4.240"` in NSPasteboard + `keystroke "v" using command down`. Bypasses IME. Side effect: overwrites user clipboard — save+restore pattern required.
2. **Tier 2 (fallback)**: AppleScript `tell application "System Events" to set selectedInputSource to ABC` → force to ABC input source → keystroke → restore original input source. Side effect: briefly changes user's input source (~100ms). May be visually jarring if user is typing Korean.
3. **Tier 3 (last resort, real Unicode)**: `CGEventKeyboardSetUnicodeString` API — truly IME-agnostic Unicode event injection. Create a `CGEvent` then call `CGEventKeyboardSetUnicodeString(event, length, &chars)`. Different from the existing `CGEventChannel.keyStroke(for: ".")` keycode 47 approach — keycode is layout-dependent; Unicode injection is OS-layer string injection. Requires a new helper `CGEventChannel.postUnicodeString(_ s: String, pid: pid_t)`.

> The existing `CGEventChannel.keyStroke(for: ".")` (keycode 47) is based on ASCII input layout and behavior is not guaranteed with IME active. The v3.2 new Tier 3 is a separate API.

Tier 1/2/3 selection depends on T0 spike results. Confirmed in PRD v0.3.

## 4. Functional Requirements

### 4.1 Navigation accuracy (FR-1)

When `transport.goto_position { position: "B.B.D.T" }` is called (after TransportDispatcher validation passes and routing occurs):

- **AC-1.1**: `position` is 4-component canonical (`"146.4.4.240"`, bar 1..9999, beat 1..16, sub 1..16, tick 1..999) → all 4 components are delivered to the dialog; playhead reaches the precise sub-bar position. **This AC assumes §3.4 T0 spike PASS**.
- **AC-1.2 [REMOVED in v0.2]**: 1-component back-compat — TransportDispatcher already rejects. Fake back-compat removed.
- **AC-1.3**: `position` is timecode (`"00:01:30:00"`) — TransportDispatcher validation passes → ChannelRouter traverses `[.accessibility, .mcu, .coreMIDI, .cgEvent]`. AX does not support timecode → AX channel error → MCU channel error (no `transport.goto_position` mapping) → CoreMIDI channel reject → CGEvent keystroke (existing). Result: user receives timecode `"00:01:30:00"` via automatic keystroke. Precise SMPTE nav requires a separate `mmc.locate` call (currently a separate op). v3.2 does not add automatic routing (out-of-scope).
- **AC-1.4**: Integer `bar` input — compatibility maintained (existing callers). Delivered to dialog as bar.1.1.1 (existing behavior).
- **AC-1.5**: Dialog disabled (empty project) → slider fallback. Sets bar slider + beat slider. div/tick ignored. Honest Contract `readback_unavailable` + extras `precision: "bar_beat"` explicitly stated (boomer P1-3 — no new reason added).
- **AC-1.6**: Dialog timeout / DIALOG_NOT_READY → State C error. Slider fallback attempted.

### 4.2 Input validation (FR-2)

- **AC-2.1**: TransportDispatcher `isValidPositionString` rejects 1–3 / 5+ components (existing behavior preserved). No additional validation needed in v3.2.
- **AC-2.2**: bar 1..9999, beat 1..16, sub 1..16, tick 1..999 (existing). Reject 0 or negative.
- **AC-2.3**: Reject non-ASCII digits (existing — uses failable `Int(_:)`. Consistent with v3.1.11 parser).
- **AC-2.4**: AX channel `gotoPositionViaBarSlider` extracts all 4 components, but only AC-2.1-validated input reaches it → guard simplified.

### 4.3 Marker provenance (FR-3 — Boomer P1-2 + P2-1)

- **AC-3.1**: Add `positionSource: PositionSource` field to `MarkerState` (enum):
  ```swift
  enum PositionSource: String, Codable, Sendable {
      case parser    // canonical — parseMarkerListPosition success
      case fallback  // manufactured — \(index+1).1.1.1
      case unknown   // legacy snapshot pre-v3.2 — prevents boomer P1-2 false provenance
  }
  ```
- **AC-3.2**: Surface `position_source` (snake_case JSON, camelCase Swift) in `logic://markers` JSON.
- **AC-3.3**: `is_canonical: Bool` JSON-only **derived** field — true when `position_source == "parser"`. **Not stored** (boomer P2-1).
- **AC-3.4**: Existing `position` field behavior preserved (back-compat). Only the source enum is newly stored.
- **AC-3.5**: Codable backward-compat — when decoding existing v3.1.x cache snapshots where `position_source` is missing → decode as `.unknown` (boomer P1-2 — `.parser` default would be false provenance). New markers always explicitly use `.parser` or `.fallback`.
- **AC-3.6**: When `goto_marker` routes to a marker with `position_source ∈ {.fallback, .unknown}`, the response extras surface `marker_position_uncertain: true` + `marker_position_source: "fallback"|"unknown"` (boomer P2-2 — JSON merge explicitly specified).

### 4.4 Coding conventions (FR-4 — 11 principles maintained)

- **AC-4.1**: All new/modified code uses Korean comments only (no English comments added).
- **AC-4.2**: Zero new TODO/FIXME/XXX entries (grep verified).
- **AC-4.3**: Zero parser changes — v3.1.11 strict 4-component policy preserved. Only caller side modified.
- **AC-4.4**: SOLID/SRP — `parseFourComponentPosition` extracted as a separate function (different responsibility from parser function — extracts caller input).
- **AC-4.5**: Compact — new function bodies ≤ 25 lines.
- **AC-4.6**: Zero regressions on existing dialog/slider fallback behavior (all existing testServerVersionMatches + dialog tests PASS).

## 5. Non-Functional Requirements

### 5.1 Performance

- **AC-5.1**: Dialog path latency change — adding Tier 1 pasteboard paste adds < 100ms. Measurement required (live-verify Tier 1).
- **AC-5.2**: Serialization overhead from additional cache schema fields < 5%.

### 5.2 Backward compatibility

- **AC-6.1**: Existing `transport.goto_position { bar: 5 }` behavior preserved (TransportDispatcher line 90 branch).
- **AC-6.2 [REMOVED in v0.2]**: 1-component position rejection preserved. False back-compat claim removed.
- **AC-6.3**: Existing `goto_marker` behavior preserved (routes the position string from cache directly to transport.goto_position).
- **AC-6.4**: MarkerState Codable: `position_source` missing → decode as `.unknown` (backward-compatible with existing cache snapshots + prevents false provenance).

### 5.3 Test coverage

- **AC-7.1**: 4-component dialog path unit test (synthetic AppleScript runtime).
- **AC-7.2**: Slider fallback partial (bar+beat) test → validates `readback_unavailable` + `precision: "bar_beat"`.
- **AC-7.3**: Provenance: 3-case cache snapshot test for parser-success / parser-fail / legacy-snapshot.
- **AC-7.4**: `goto_marker { name: "X" }` E2E: when cache has `position_source ∈ {.fallback, .unknown}`, validates response extras `marker_position_uncertain: true`.
- **AC-7.5**: Existing 1064 + new ≥ 10 cases = 1074+ PASS.
- **AC-7.6**: T0 live spike results permanently recorded in `live-verify-v3.2.0.md` Tier 2.

## 6. Implementation Plan (ticket breakdown v0.2)

| # | Title | Size | Dependencies |
|---|-------|------|--------------|
| **T0** | **Live spike (release gate)**: 4-component dialog verification + 3 IME scenarios | S (manual) | — |
| T1 | `parseFourComponentPosition` helper (extracts caller input — validation belongs to dispatcher) | S | T0 PASS |
| T2 | `gotoPositionViaBarSlider` 4-component extension (dialog + slider partial fallback) **+ AppleScript runner test seam** | M | T1 |
| T2a | **IME mitigation Tier 1 (pasteboard paste)** — conditional on T0 S3 FAIL | S | T0, T2 |
| T2b | **IME mitigation Tier 3 (CGEventKeyboardSetUnicodeString)** — conditional on T0 S1 FAIL | M | T0, T2 |
| T3 | `MarkerState.positionSource` enum (parser/fallback/unknown) + Codable backward compat | S | — |
| T4 | `extractMarkerPosition` **both fallback sites** (legacy ruler L708 + Logic 12.2 markerListWindow L798-800) marked `.fallback` | S | T3 |
| T5 | `logic://markers` resource envelope surfaces `position_source` + derived `is_canonical` (Encodable DTO + `jsonStringEscape`) | S | T3 |
| T6 | `goto_marker` dispatcher: when routing fallback/unknown marker → **HC top-level extras merge** (`marker_position_uncertain` + `marker_position_source`) | S | T2, T4 |
| T7 | Parameterized matrix + integration regression tests (1074+ tests) | M | T1, T2, T3, T4, T5, T6 |
| T8 | TROUBLESHOOTING + CHANGELOG + **docs/API.md** (`MarkerState` schema + `goto_marker` extras + `goto_position` behavior spec) + README + version bump 3.1.11 → 3.2.0 | M | T7 |
| T9 | live-verify-v3.2.0 runbook (T0 results permanently recorded + IME scenarios + dialog 4-component + slider partial) | S | T7 |
| T10 | Release v3.2.0 + final report | S | T8, T9 |

> **Version decision**: provenance field is a backward-compat addition, but navigation accuracy is a **new capability** → minor bump (3.1.11 → 3.2.0). Boomer agreed.

## 7. Risks & Mitigations (v0.2)

| Risk | Severity | Mitigation |
|------|---------|-----------|
| AppleScript `keystroke "146.4.4.240"` drops `.` in Korean IME | High | T0 spike + 3-tier mitigation (§3.5). Tier 1: pasteboard paste, Tier 2: force ABC input source, Tier 3: CGEvent Unicode |
| Logic dialog rejects 4-component input | High | Primary verification in T0 spike. If rejected, reduce nav scope (rewrite PRD v0.3) |
| Div/tick sliders not present in control bar | Low | Zero attempts to set div/tick — intentionally partial. extras `precision: "bar_beat"` stated |
| MarkerState Codable change breaks existing cache snapshot decoding | Medium | `.unknown` default + custom decoder + Codable round-trip test required |
| goto_marker response schema change breaks existing clients | Low | Additions to extras only (zero existing field changes). Documented in CHANGELOG. No impact on existing clients |
| Pasteboard paste side effect (overwrites user clipboard) | Medium | save+restore pattern — read NSPasteboard.general immediately before paste, restore after 0.1s delay post-paste |

## 8. Edge Cases (E1-E13 v0.2)

| # | Input | Expected Behavior |
|---|-------|------------------|
| E1 | `position: "146.4.4.240"` | dialog → precise sub-bar |
| E2 | `position: "1.1.1.1"` | dialog → bar 1 start |
| E3 | `position: "9999.16.16.999"` | dialog → maximum bound (corrected: tick max 999, sub max 16) |
| E4 | `position: "146"` | TransportDispatcher rejects (existing behavior). Same as E5 |
| E5 | `position: "146.4"` | TransportDispatcher rejects (existing) |
| E6 | `position: "146.4.4"` | TransportDispatcher rejects (existing) |
| E7 | `position: "146.4.4.240.1"` | TransportDispatcher rejects (existing) |
| E8 | `position: "0.1.1.1"` | TransportDispatcher rejects (existing — bar 1..9999) |
| E9 | `position: "10000.1.1.1"` | TransportDispatcher rejects (existing) |
| E10 | `position: "146.17.4.240"` | TransportDispatcher rejects (existing — beat 1..16) |
| E11 | `position: "00:01:30:00"` | TransportDispatcher passes → ChannelRouter AX/MCU/CoreMIDI reject → CGEvent keystroke fallback (existing). Precise SMPTE requires separate `mmc.locate` |
| E12 | `bar: 146` (legacy caller) | dialog → bar 146 (existing) |
| E13 | Empty project (dialog disabled) | Slider fallback bar+beat partial. State B `readback_unavailable` + `precision: "bar_beat"` |

## 9. 11-Principle Mapping (Isaac directive)

| # | Principle | Application |
|---|-----------|-------------|
| 1 | Silicon Valley top 0.1% | T0 spike + 4-agent × 3 review phases (PRD + tickets + final) + live e2e |
| 2 | Apple standard | Foundation + AppleScript + NSPasteboard + CGEventKeyboardSetUnicodeString (official Apple IME-agnostic API). Pure function separation, body ≤ 25 lines |
| 3 | 0.1% edge cases zero | E1-E13 + parameterized matrix + 3 IME scenarios |
| 4 | No over-engineering | Fake back-compat ACs removed (boomer P1-4); zero div/tick slider additions; `is_canonical` derived |
| 5 | Zero dead code | grep + git diff verify |
| 6 | Compact | 1 helper function, dispatcher changes ≤ 30 lines |
| 7 | Standard references | Swift API Design Guidelines (parseFourComponentPosition naming) |
| 8 | Junior readability | Korean step-by-step comments + 3-tier mitigation explicitly stated |
| 9 | Korean comments | All new/modified code |
| 10 | SOLID/SRP | Parser handles AX surface conversion / new helper handles caller validation / dispatcher handles routing |
| 11 | Compact | Parameterized matrix reduces case-by-case + extras consolidated |

## 10. Success Metrics

- 1064 → 1074+ tests PASS
- `swift build -c release` 0 warnings
- `goto_marker { name: "VOCALS" }` live (Logic 12.2 English/Korean + IME ON 3 scenarios) → playhead reaches precise sub-bar (visual + observed ratio ≥ 95% match)
- `logic://markers` response includes `position_source` field 100%
- Boomer P2-3 closed
- v3.1.11 NG10 closed
- AC-4.2 grep TODO/FIXME 0
- T0 live spike results PASS 3/3 (English / Korean IME OFF / Korean IME ON)

## 11. Approvals

- [x] Boomer BOOMER-6 (PRD v0.1) — REQUEST CHANGES (P0+4P1+2P2)
- [x] Boomer BOOMER-6 (PRD v0.2) — REQUEST CHANGES (2P1+1P2 round 2)
- [x] Boomer BOOMER-6 (PRD v0.3) — REQUEST CHANGES (1P1+1P2 round 3)
- [ ] Boomer BOOMER-6 (PRD v0.4) — pending re-review
- [ ] Strategist (PRD round 1)
- [ ] Guardian (PRD round 1)
- [ ] Tester (tickets round 1)
- [ ] Isaac final approval

## Version History

- **v0.1** (2026-05-07): Initial draft — awaiting 4-agent review input.
- **v0.2** (2026-05-07): Boomer BOOMER-6 integrated — P0 (T0 spike gate) + P1-1 (IME 3-tier mitigation) + P1-2 (`.unknown` enum default) + P1-3 (`readback_unavailable` + `precision` extras — avoids adding new reason) + P1-4 (1-component back-compat AC removed) + P2-1 (`is_canonical` derived) + P2-2 (extras shape explicitly specified).
- **v0.3** (2026-05-07): Boomer round 2 integrated — AC-1.3 SMPTE routing corrected to reflect facts (CGEvent fallback explicitly stated — MCU has no `transport.goto_position` mapping noted) + Tier 3 IME mitigation `CGEventKeyboardSetUnicodeString` actual API clarified (distinguished from existing keystroke keycode 47) + T8 scope expanded (docs/API.md `MarkerState` schema + `goto_marker` extras + `goto_position` behavior spec included).
- **v0.4** (2026-05-07): Boomer round 3 — E11 edge case synchronized with AC-1.3 (CGEvent keystroke fallback explicitly stated) + §9 principle #2 actual API list (NSPasteboard + CGEventKeyboardSetUnicodeString added). ALL PASS expected.
