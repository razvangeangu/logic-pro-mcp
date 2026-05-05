# T4: ResourceHandlers tier-merge for project_info

**PRD Ref**: PRD-issue7-logic12-read-paths > US-1 (AC-1.1..1.6, AC-4.1, AC-4.2)
**Priority**: P0 (Blocker — main user-facing fix)
**Size**: M (2-3h)
**Status**: Todo
**Depends On**: T1, T2, T3

---

## 1. Objective
Rewrite `ResourceHandlers.readProjectInfo` to merge tiers (cache → file → defaults) at resource layer. File data feeds via T1; envelope gains `source` + `last_saved_age_sec` via T3 extras. Cache is **read-only** here (boomer P0 — never write file/placeholder data into cache).

## 2. Acceptance Criteria

**Cache freshness rule (concrete)**: cache is "fresh" iff `info.lastUpdated > .distantPast`. This is set when StatePoller successfully decodes a ProjectInfo. Defaults case (`.distantPast`) means poller never wrote real data.

- [ ] AC-1: cache fresh (lastUpdated > .distantPast) → use cache values; envelope `source: "ax_live"` if `cacheAgeSec < 5` else `"cache"`.
- [ ] AC-2: cache is at struct defaults (lastUpdated == .distantPast) AND LogicProjectFileReader returns metadata → use file values; envelope `source: "project_file"` + `last_saved_age_sec`.
- [ ] AC-3: cache fresh tempo=95 AND file tempo=80 → response 95 (cache wins per AC-1), source `"ax_live"` or `"cache"` per age. **NEVER** mixes file value into ProjectInfo when cache is fresh.
- [ ] AC-4: cache stale AND file unreadable → ProjectInfo defaults; envelope `source: "default"`.
- [ ] AC-5: existing JSON consumers (no `source`/`last_saved_age_sec` access) still pass.
- [ ] AC-6: response wraps in envelope (was bare JSON in v3.1.7) — `wrapWithCacheEnvelope` with extras.
- [ ] AC-7: existing `testProjectInfoResourceIncludesMetadata` updated to read `data.name` from envelope; passes.

## 3. TDD Spec (Red Phase)

### 3.1 Test Cases
File: `Tests/LogicProMCPTests/ResourceProjectInfoTierMergeTests.swift` (new)

| # | Test Name | Type | Expected |
|---|-----------|------|----------|
| 1 | `cacheLive_filePresent_cachePreferred_sourceCacheOrAxLive` | Unit | cache tempo=95 + file tempo=80 → tempo=95, source not project_file |
| 2 | `cacheDefault_fileMetadata_useFile_sourceProjectFile` | Unit | cache fresh? no → file 80/4-4/31 → response 80/4-4/31, source `project_file`, has `last_saved_age_sec` |
| 3 | `cacheDefault_fileUnreadable_useDefaults_sourceDefault` | Unit | both empty → defaults, source `default` |
| 4 | `cachePartial_fileFills_mergeBothPaths` | Unit | cache has only `name` set; file fills tempo + tsig + count → merge, source per dominant tier |
| 5 | `envelopeShape_extrasIncludesSource` | Unit | extras key `source` always present |
| 6 | `envelopeShape_lastSavedAgeSecOnlyWhenFile` | Unit | extras `last_saved_age_sec` absent when source ≠ `project_file` |
| 7 | `existingResourceTest_includesEnvelopeWrappedData` | Integration | `testProjectInfoResourceIncludesMetadata` updated to read `data.name`; passes |

### 3.2 Mock/Setup
- Inject `LogicProjectFileReader.Runtime` via `ResourceHandlers.read(...)` — see Implementation §4.1 for plumbing strategy
- Build StateCache directly with `await cache.updateProject(...)` for live cache tests

## 4. Implementation Guide

### 4.1 Files to Modify
| File | Change | Description |
|------|--------|-------------|
| `Sources/LogicProMCP/Resources/ResourceHandlers.swift` | Modify | rewrite readProjectInfo |
| `Sources/LogicProMCP/Resources/ResourceProvider.swift` | Modify | inject reader into resource read calls (or use static .production) |
| `Tests/LogicProMCPTests/ResourceProjectInfoTierMergeTests.swift` | Create | 7 tests |
| `Tests/LogicProMCPTests/ResourceSchemaTests.swift` | Modify | update existing test for envelope wrap |

### 4.2 Implementation Steps (Green)
1. Add `LogicProjectFileReader.Runtime` parameter to `ResourceHandlers.read(...)` (default `.production`).
2. In `readProjectInfo`:
   - Read cache.getProject() and cache.getProjectFetchedAt().
   - Decide cache freshness: `lastUpdated > .distantPast` AND not all-defaults.
   - If cache fresh → use cache values; source="ax_live" (if recent) or "cache" (if older). Skip file read for performance.
   - Else → call `await fileReader.read()`. If returns metadata, populate ProjectInfo fields from file. source="project_file", extras include `last_saved_age_sec`.
   - Else → ProjectInfo defaults. source="default".
3. Wrap with `wrapWithCacheEnvelope(bodyJSON: encodeJSON(info), fetchedAt: info.lastUpdated, axOccluded: ax, extras: ["source": source, ...])`.
4. Call `cache.updateProjectFetchedAt(now)` IS NOT done here — read-only.

### 4.3 Refactor Phase
- Extract a `ProjectInfoTierMerge` private helper if logic exceeds 60 LOC.

## 5. Edge Cases (PRD §5)
- E1, E2, E3, E4, E5, E13, E15, E21 (path mid-read switch)

## 6. Review Checklist
- [ ] Red: 7 tests fail (existing handler doesn't tier-merge or wrap)
- [ ] Green: 7 tests pass; existing schema test updated; full suite green
- [ ] cache integrity: writing to file path NEVER calls `cache.updateProject` from resource layer
- [ ] envelope wraps even on error / empty path
