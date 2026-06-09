# T7: Issue7IntegrationTests — cross-tier scenarios

> Historical record (2026-06-09 docs refresh): latest production-readiness and live E2E evidence is in `README.md`, `CHANGELOG.md`, and `docs/live-verify-v3.4.5.md`; this file remains preserved implementation context.

**PRD Ref**: PRD-issue7-logic12-read-paths > §8.2
**Priority**: P1 (High)
**Size**: M (2h)
**Status**: Todo
**Depends On**: T4, T5, T6

---

## 1. Objective
End-to-end tests covering all tier-merge scenarios via injected runtime — exercising the v3.1.4 / v3.1.5 / v3.1.6 / v3.1.7 regression scenarios + new fix paths.

## 2. Acceptance Criteria
- [ ] AC-1: 5 cross-resource scenarios that cover the boomer-identified P0 paths.
- [ ] AC-2: All scenarios use injected `LogicProjectFileReader.Runtime` + synthetic `StateCache` + synthetic AX tree (no real Logic dependency).
- [ ] AC-3: Each scenario produces a deterministic envelope; tests assert specific `source` values per AC matrix.

## 3. TDD Spec (Red Phase)

### 3.1 Test Cases
File: `Tests/LogicProMCPTests/Issue7IntegrationTests.swift` (new)

| # | Scenario Name | Description |
|---|---------------|-------------|
| 1 | `S1_TracksPanelFocused_LiveAxFires` | AX tree with proper Track Headers; cache populated by poller; resource `tracks` returns 31 live names; `project_info` returns ax_live values; `markers` returns ax_live array |
| 2 | `S2_MixerPanelFocused_TracksFallbackToFile` | AX tree returns Inspector-only outline; cache empty; file says 31 → tracks placeholder array; project_info from file |
| 3 | `S3_NoDocument_AllResourcesDefault` | Empty cache + nil current path → all 3 resources return defaults |
| 4 | `S4_LiveCacheVsStaleFile_CacheWins` | cache project tempo=95 fresh + file=80 → response 95 (NEVER mixed) |
| 5 | `S5_PlaceholderEmission_DoesNotPoisonCache` | cache empty initially → readTracks emits placeholders → cache.getTracks() afterwards still returns `[]` (poisoning negated) |

### 3.2 Mock/Setup
- Reuse `FakeAXRuntimeBuilder` from existing test support
- Build synthetic plist files in tmpdir for file-tier
- Inject all into `ResourceHandlers.read(...)`

## 4. Implementation Guide

### 4.1 Files to Modify
| File | Change | Description |
|------|--------|-------------|
| `Tests/LogicProMCPTests/Issue7IntegrationTests.swift` | Create | 5 scenario tests |
| `Tests/LogicProMCPTests/AccessibilityTestSupport.swift` | Modify (optional) | Add helper to build "Inspector-only" tree for S2 |

### 4.2 Implementation Steps (Green)
1. For each scenario, build AX tree, cache state, file system fixture.
2. Call `ResourceHandlers.read(uri:cache:router:fileReader:)` with full injection.
3. Parse envelope JSON, assert each field per scenario expectations.
4. After each call, inspect cache state to verify no poisoning (S5).

## 5. Edge Cases
Already covered by underlying tickets; this is integration-level coverage.

## 6. Review Checklist
- [ ] Red: 5 scenarios fail (handlers not yet rewired)
- [ ] Green: 5 scenarios pass after T4+T5+T6 are merged
- [ ] No flakiness — deterministic clock injection
