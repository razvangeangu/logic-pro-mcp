# T5: ResourceHandlers tier-merge for tracks + placeholder rows

> Historical record (2026-06-05 docs refresh): latest production-readiness and live E2E evidence is in `README.md`, `CHANGELOG.md`, and `docs/live-verify-v3.4.5-rc5.md`; this file remains preserved implementation context.

**PRD Ref**: PRD-issue7-logic12-read-paths > US-2 (AC-2.1..2.5), G5 (cache-no-poison)
**Priority**: P0 (Blocker)
**Size**: M (2h)
**Status**: Todo
**Depends On**: T1, T2, T3

---

## 1. Objective
Rewrite `ResourceHandlers.readTracks` to surface placeholder track rows from `MetaData.plist`'s `NumberOfTracks` when AX cache is empty/occluded. **Critical: placeholder rows MUST NOT be written back to cache.**

## 2. Acceptance Criteria
- [ ] AC-1 (AC-2.1): cache has 31 live tracks → 31 real rows, `placeholder: false`, `source: "ax_live"`.
- [ ] AC-2 (AC-2.2): cache empty + file `NumberOfTracks=31` → 31 rows with `name == "Track 1".."Track 31"`, `placeholder: true`, `source: "ax_live_with_file_count"` (or `"project_file"` if no live data exists at all in cache history).
- [ ] AC-3 (G5): test asserts `await cache.getTracks()` is **unchanged** after the placeholder branch — cache stays at the live-cache state (could be `[]`).
- [ ] AC-4 (AC-2.3): cache has 12 entries, all names ending in `:` (Inspector field labels) → response is empty (or file count) — never the field labels. Hardened heuristic: **if `tracks.count >= 3` AND `tracks.allSatisfy { $0.name.hasSuffix(":") }`** → treat as Inspector subtree contamination, drop them. Threshold of 3 prevents false-positive on a legitimate single track named "MyMix:".
- [ ] AC-5 (AC-2.4): Logic not running → `[]`, source `default`.
- [ ] AC-6 (AC-2.5): plist corrupt → cache fallthrough → `[]`.
- [ ] AC-7: envelope `source` always present; cached envelope `placeholder` per-row.

## 3. TDD Spec (Red Phase)

### 3.1 Test Cases
File: `Tests/LogicProMCPTests/ResourceTracksTierMergeTests.swift` (new)

| # | Test Name | Type | Expected |
|---|-----------|------|----------|
| 1 | `cacheLive_31tracks_realNames_sourceAxLive` | Unit | cache populated → 31 rows, placeholder=false, source `ax_live` |
| 2 | `cacheEmpty_fileCount31_emits31Placeholders` | Unit | cache empty + file=31 → 31 rows `Track 1..31`, placeholder=true, source `ax_live_with_file_count` |
| 3 | `cacheEmpty_fileMissing_emitsEmpty` | Unit | both empty → `[]`, source `default` |
| 4 | `g5_cacheUnpoisoned_afterPlaceholderEmit` | Integration | call readTracks twice; cache.getTracks() before+after must equal `[]` (live cache state) |
| 5 | `cacheInspectorContamination_allNamesColon_dropAndFallback` | Unit | cache has 12 entries `Mute:`, `Loop:`, ... → response is empty (or file count); inspector data NOT surfaced |
| 6 | `cacheLive12_fileSays40_useCache12` | Unit | live cache has 12 real entries; file says 40 → respond with 12 real (cache wins) |
| 7 | `envelopeExtras_sourceAndPlaceholderFlag` | Unit | envelope contains `source` extra; rows contain `placeholder` field |

### 3.2 Mock/Setup
- StateCache instances seeded via `await cache.updateTracks([...])`
- LogicProjectFileReader.Runtime injected with mock metadata returning specific track counts

## 4. Implementation Guide

### 4.1 Files to Modify
| File | Change | Description |
|------|--------|-------------|
| `Sources/LogicProMCP/Resources/ResourceHandlers.swift` | Modify | rewrite readTracks |
| `Sources/LogicProMCP/State/StateModels.swift` | Modify | add `placeholder: Bool` to TrackState |
| `Tests/LogicProMCPTests/ResourceTracksTierMergeTests.swift` | Create | 7 tests |

### 4.2 Implementation Steps (Green)
1. Add `var placeholder: Bool = false` to `TrackState` (default false; backward-compat).
2. In `readTracks`:
   - `let liveTracks = await cache.getTracks()`
   - Inspector contamination heuristic: if `liveTracks.count >= 3 AND liveTracks.allSatisfy { $0.name.hasSuffix(":") }` → set effective `liveTracks = []`
   - If `liveTracks` non-empty → return as-is, source `"ax_live"`
   - Else → `let metadata = await fileReader.read()`
     - If `metadata?.trackCount ?? 0 > 0` → emit `(0..<count).map { TrackState(id: $0, name: "Track \($0+1)", type: .unknown, placeholder: true) }`
     - source: `"ax_live_with_file_count"` if `cache.getTracksFetchedAt() > .distantPast` (poller ran but came up empty), else `"project_file"` (poller never ran or cache flushed)
   - Else → empty array, source `"default"`
   - **Critical (G5)**: NEVER call `await cache.updateTracks(...)` from this function.
3. Wrap envelope with `extras: ["source": <value>]`.
4. **Do NOT** write to cache from this path.

### 4.3 Refactor Phase
- Extract `inspectorContaminationDetector` helper if reused.

## 5. Edge Cases
- E10 (Inspector contamination): handled in step 2
- E11 (legitimate `Untitled` names): does NOT match inspector heuristic (not all end in `:`)
- E15 (concurrent reads): stateless tier-merge

## 6. Review Checklist
- [ ] Red: 7 tests fail
- [ ] Green: 7 tests pass; existing track tests unaffected (placeholder=false implicit)
- [ ] G5 verified: cache unchanged after placeholder emission
- [ ] Heuristic doesn't false-trigger on `Audio:` track names (case sensitive: only suffix `:` after name)
