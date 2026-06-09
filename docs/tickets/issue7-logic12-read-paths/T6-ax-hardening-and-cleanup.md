# T6: AX hardening (tracks + markers) + delete dead AppleScript-primary helpers

> Historical record (2026-06-09 docs refresh): latest production-readiness and live E2E evidence is in `README.md`, `CHANGELOG.md`, and `docs/live-verify-v3.4.6.md`; this file remains preserved implementation context.

**PRD Ref**: PRD-issue7-logic12-read-paths > US-3, AC-2.3, NG4 (revised)
**Priority**: P0 (Blocker)
**Size**: M (2-3h)
**Status**: Todo
**Depends On**: None (parallel-safe with T1-T5)

---

## 1. Objective
1. Tighten `AXLogicProElements.getTrackHeaders` so the fallback at lines 325-330 (any `AXOutline` / `AXTable`) cannot match the Inspector subtree.
2. Tighten `AXLogicProElements.enumerateMarkers` to identify the marker ruler by `AXRole` + structural position rather than the language-specific `marker` / `마커` identifier string.
3. Delete the dead AppleScript-primary helpers (`markersViaAppleScript`, `projectInfoViaAppleScript`, `tracksViaAppleScript`) and their `AccessibilityChannel.Runtime` wiring.

## 2. Acceptance Criteria
- [ ] AC-1 (Tracks hardening): `getTrackHeaders` returns nil if no element has identifier "Track Headers" / "트랙 헤더" AND no element has children with `kAXLayoutItemRole`. The unconditional `findDescendant(of: window, role: kAXOutlineRole)` fallback is gated.
- [ ] AC-2 (Markers hardening): `enumerateMarkers` locates the marker ruler by:
   - First: `AXRole == "AXRuler"` + structural position (sibling of timeline ruler within the arrange area)
   - Fallback: existing language-keyword match (preserves Logic 11.x behaviour)
- [ ] AC-3 (Cleanup): All three `*ViaAppleScript` static functions deleted from `AccessibilityChannel.swift`. The Runtime fields `markersAppleScript`, `projectInfoAppleScript`, `tracksAppleScript` and their initialiser parameters deleted. The `axBacked()` factory updated.
- [ ] AC-4: `AccessibilityChannel.execute` calls for `track.get_tracks` / `nav.get_markers` / `project.get_info` no longer reference AppleScript-primary closures — they call the AX-default closures directly.
- [ ] AC-5: All tests in `AccessibilityChannelAppleScriptReadsTests.swift` deleted (the file is removed).
- [ ] AC-6: `axBackedRuntimeWiresAppleScriptHelpers` test removed.
- [ ] AC-7: Test count must stay green (only deletions; no behavioural regression for AX path).

## 3. TDD Spec (Red Phase)

### 3.1 Test Cases — Tracks
File: `Tests/LogicProMCPTests/AXTracksHardeningTests.swift` (new, replaces removed tests)

| # | Test Name | Type | Expected |
|---|-----------|------|----------|
| 1 | `getTrackHeaders_identifierMatch_returns` | Unit | synthetic AX tree with group having description "Track Headers" → returned |
| 2 | `getTrackHeaders_layoutItemChildren_returns` | Unit | AX tree with table whose children are `AXLayoutItem` → returned |
| 3 | `getTrackHeaders_inspectorOnly_returnsNil` | Unit | AX tree with only Inspector outline (no layout items, no track-headers identifier) → nil |
| 4 | `defaultGetTracks_inspectorOnly_returnsEmpty` | Unit | runtime with such tree → empty `[]` |

### 3.2 Test Cases — Markers
File: `Tests/LogicProMCPTests/AXMarkersHardeningTests.swift` (new)

| # | Test Name | Type | Expected |
|---|-----------|------|----------|
| 5 | `markers_axRulerSibling_returnsMarkers` | Unit | AX tree with AXRuler sibling of timeline AXRuler containing AXStaticText markers → markers returned |
| 6 | `markers_languageFallback_returnsMarkers` | Unit | AX tree with group description "marker ruler" (Logic 11.x style) → still returned |
| 7 | `markers_noRuler_returnsEmpty` | Unit | AX tree with no AXRuler → empty |

### 3.3 Existing tests deleted
- `Tests/LogicProMCPTests/AccessibilityChannelAppleScriptReadsTests.swift` (16 tests removed)
- `axBackedRuntimeWiresAppleScriptHelpers` (1 test removed)

Net test delta: +7 -17 = -10 (acceptable; Phase 1-5 totals must net positive overall).

## 4. Implementation Guide

### 4.1 Files to Modify
| File | Change | Description |
|------|--------|-------------|
| `Sources/LogicProMCP/Accessibility/AXLogicProElements.swift` | Modify | tighten getTrackHeaders + enumerateMarkers |
| `Sources/LogicProMCP/Channels/AccessibilityChannel.swift` | Modify | delete 3 helper functions + Runtime fields |
| `Tests/LogicProMCPTests/AccessibilityChannelAppleScriptReadsTests.swift` | Delete | obsoleted by NG4 |
| `Tests/LogicProMCPTests/AXTracksHardeningTests.swift` | Create | 4 tests |
| `Tests/LogicProMCPTests/AXMarkersHardeningTests.swift` | Create | 3 tests |

### 4.2 Implementation Steps (Green)
1. **getTrackHeaders tightening** (AXLogicProElements.swift:300-332):
   - Keep identifier-based "Track Headers" lookup (line 304) — AC-1 case 1
   - Keep group description "track headers" / "트랙 헤더" lookup (lines 317-323) — AC-1 case 1
   - Replace the unconditional outline/table fallback at lines 325-330 with: only return outline/table IF its children include at least one `kAXLayoutItemRole` element. Otherwise return nil.
2. **enumerateMarkers hardening** (line 606+):
   - First strategy: find all `AXRuler` elements; if 2+, the second is the marker ruler (timeline first). Pluck markers from there.
   - Fallback: existing `markerKeywords` loop. Keep for 11.x compatibility.
3. **Delete AppleScript-primary helpers** (AccessibilityChannel.swift):
   - Functions at lines 3083, 3133, 3203 — remove (lines ~3080-3330 of the helper region; keep `parseAppleScriptResult`, `parseMarkerRecords`, `formatBeatsAsBarPosition`, `appleScriptBool` if still used elsewhere; otherwise remove).
   - Runtime fields at lines 77, 78, 79 — remove.
   - Runtime initialiser params at lines 101, 102, 103 — remove.
   - `axBacked()` factory wiring at lines 157, 160, 166 — remove.
   - `track.get_tracks` (~241), `nav.get_markers` (~431), `project.get_info` (~447) — drop AppleScript primary call; only call the AX default closure.
4. **Test cleanup**: delete `AccessibilityChannelAppleScriptReadsTests.swift`. Delete `axBackedRuntimeWiresAppleScriptHelpers` test (likely in `AccessibilityChannelTests.swift`).

### 4.3 Refactor Phase
- After delete, scan for any remaining references to the deleted helpers — should be zero.

## 5. Edge Cases (PRD §5)
- E10 (Inspector subtree): step 1 prevents the false-positive
- E12 (12.3+ adds dictionary back): irrelevant — we no longer use AppleScript-primary

## 6. Review Checklist
- [ ] Red: 7 new tests fail (hardening not yet implemented)
- [ ] Green: 7 new tests pass; deleted tests don't run; full suite green
- [ ] Build clean — no orphan references to deleted symbols
- [ ] `track.get_tracks` against synthetic Inspector-only tree returns empty (not field labels)
- [ ] `defaultGetMarkers` against keyword-stripped 12.x AX tree returns markers via AXRuler path
