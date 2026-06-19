# T8 — TROUBLESHOOTING + CHANGELOG + docs/API.md + README + Version Bump 3.2.0

> Historical record. Current release-candidate evidence is in `README.md`, `CHANGELOG.md`, and `docs/live-verify-v3.6.0.md`; published stable evidence remains in `docs/live-verify-v3.5.0.md`; this file remains preserved implementation context.

**Status**: Todo
**Depends on**: T1-T7
**Size**: M
**PRD**: §6 (T8 expanded scope), Boomer round 2 P2

## Files to Change

| File | Change |
|------|--------|
| `Sources/LogicProMCP/Server/ServerConfig.swift` | `serverVersion = "3.2.0"` |
| `Formula/logic-pro-mcp.rb` | `version "3.2.0"` (sha256 patched by release.sh) |
| `manifest.json` | version `3.2.0` |
| `Scripts/install.sh` | version label `3.2.0` |
| `README.md` | add v3.2.0 entry to Status section |
| `CHANGELOG.md` | add `## [3.2.0] — 2026-MM-DD` |
| `docs/TROUBLESHOOTING.md` | add `goto_marker` accuracy + provenance entries |
| `docs/API.md` | `MarkerState` schema (includes positionSource) + `logic_navigate.goto_marker` routing + extras documented + `logic_transport.goto_position` 4-component behavior spec |

## docs/API.md Key Changes

Before (line 369-371):
```ts
// MarkerState (polled into cache, also available in logic://project/info)
{ id: int, name: string, position: string }
```

After:
```ts
// MarkerState (v3.2 schema)
{
  id: int,
  name: string,
  position: string,                              // "bar.beat.div.tick" canonical
  position_source: "parser"|"fallback"|"unknown",  // provenance
  is_canonical: boolean                          // derived: position_source == "parser"
}
```

`goto_marker { name: ... }` routing row:
```
| `goto_marker` | `{ name: string }` or `{ index: int }` | text | By name: cache lookup → transport.goto_position (4-component dialog/slider). When marker has fallback/unknown provenance, response extras include `marker_position_uncertain: true` |
```

`goto_position` routing row (line 72) — 4-component dialog path precision documented (Boomer P2-2 fix: accurate notation — `bar.beat.div.tick` 1..9999 / 1..16 / 1..16 / 1..999):
```
| `goto_position` | `{ bar: int }` (1..9999) or `{ position: string }` — `"bar.beat.div.tick"` (1..9999, 1..16, 1..16, 1..999) precise sub-bar nav or `"HH:MM:SS:FF"` SMPTE (CGEvent fallback) | text | Accessibility (4-component dialog → bar+beat slider partial) → CGEvent (timecode) |
```

## CHANGELOG Entry Draft

```markdown
## [3.2.0] — 2026-MM-DD

**v3.1.11 NG10 closed + Boomer P2-3 closed.** `goto_marker` now reaches the exact
sub-bar position (`bar.beat.div.tick`), and marker `position` fields surface parser
success/fallback provenance in machine-readable form.

### Changed

- `transport.goto_position` AX channel: 4-component dialog input (previously 1-component bar only)
- `MarkerState` schema: `position_source: "parser"|"fallback"|"unknown"` + derived `is_canonical: boolean` added
- `goto_marker`: routing fallback/unknown markers includes extras `marker_position_uncertain: true` + `marker_position_source`

### Codable backward compat

Decoding v3.1.x cache snapshots with missing `position_source` → `.unknown` (blocks false provenance). New markers are always `.parser` or `.fallback`.

### Implementation

- `AccessibilityChannel.parseFourComponentPosition` helper (caller validation)
- `gotoPositionViaDialog` signature: `bar: Int` → `position: FourComponentPosition`
- `gotoPositionViaSliderPartial` new — bar+beat partial, extras `precision: "bar_beat"`
- IME mitigation: Tier 0/1/2/3 based on T0 live spike results (see docs/live-verify-v3.2.0.md)

### Tests

1064 → 1074+ PASS. E1-E13 matrix + 3 cross-ticket E2E + Codable backward compat.

### Behavior change

None — back-compat false claim removed (1-component position has been rejected by the dispatcher since v3.1.x, same in v3.2).

### Honest deferred

- Logic 11.x AX surface — 12.x primary, 11.x follow-up
- Timecode precision nav — separate `mmc.locate` call required (v3.2 does not add auto-routing)
```

## README Status Addition

```markdown
**v3.2.0** (2026-MM-DD) — `goto_marker` sub-bar accuracy (NG10 closed) + Marker provenance (Boomer P2-3 closed). `MarkerState` schema gains `position_source` + `is_canonical`. v3.1.x cache snapshots decode as `.unknown` (backward compat). See [CHANGELOG §3.2.0](CHANGELOG.md#320--2026-mm-dd).
```

## Acceptance Criteria

- **AC-T8.1**: 4 version artifacts (`ServerConfig`, `Formula`, `manifest`, `install.sh`) all `3.2.0`
- **AC-T8.2**: `testServerVersionMatchesPackagingArtefacts` PASS
- **AC-T8.3**: README Status section: v3.2.0 entry as first line
- **AC-T8.4**: CHANGELOG `## [3.2.0]` section added, Unreleased section cleared
- **AC-T8.5**: docs/API.md `MarkerState` schema updated + `goto_marker` routing row updated + `goto_position` row updated
- **AC-T8.6**: TROUBLESHOOTING: `position_source` entry + `goto_marker` accuracy entry added
- **AC-T8.7**: English markdown consistency (Korean comments in code only, per user directive)
- **AC-T8.8**: 4 version artifacts (ServerConfig + Formula + manifest + install.sh) have `3.2.0` accurately — historical references (e.g., v3.1.11 CHANGELOG entries) preserved (Boomer P2-2 fix: grep AC scope limited)

## Out of Scope

- live-verify runbook = T9
- release execution = T10
