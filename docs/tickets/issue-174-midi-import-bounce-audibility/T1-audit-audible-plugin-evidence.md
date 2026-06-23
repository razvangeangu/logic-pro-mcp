# T1: Add Audit Blocker For Software Instrument Regions Without Audible Plugin Evidence

**PRD Ref**: PRD-issue-174-midi-import-bounce-audibility > US-1
**Priority**: P0 (Blocker)
**Size**: S (< 2h)
**Status**: Done
**Depends On**: None

---

## 1. Objective
Prevent MIDI-import demo/export sessions from claiming bounce readiness when software-instrument tracks have regions but no readable instrument/plugin evidence.

## 2. Acceptance Criteria
- [x] AC-1: Audit emits `software_instrument_regions_without_audible_plugin` as a blocker when software-instrument tracks with regions lack plugin evidence.
- [x] AC-2: Export readiness status becomes `blocked` and includes the blocker.
- [x] AC-3: The blocker is absent when readable plugin evidence exists for the same track.

## 3. TDD Spec (Red Phase)

### 3.1 Test Cases

| # | Test Name | Type | Description | Expected |
|---|-----------|------|-------------|----------|
| 1 | `testProjectAuditBlocksSoftwareInstrumentRegionsWithoutPluginEvidenceBeforeExportClaim` | Unit | Software-instrument track with region and no plugin evidence | Blocker finding + export readiness blocked |
| 2 | `testProjectAuditAllowsSoftwareInstrumentRegionsWithPluginEvidence` | Unit | Same region plus readable plugin evidence | No new blocker |

### 3.2 Test File Location
- `Tests/LogicProMCPTests/ProjectSessionAuditTests.swift`

### 3.3 Mock/Setup Required
- Synthetic `ProjectSessionAudit.Snapshot`
- Synthetic `ChannelStripState`

## 4. Implementation Guide

### 4.1 Files to Modify
| File | Change Type | Description |
|------|------------|-------------|
| `Sources/LogicProMCP/Workflows/ProjectSessionAudit.swift` | Modify | Add deterministic blocker over snapshot tracks/regions/mixer evidence |
| `Tests/LogicProMCPTests/ProjectSessionAuditTests.swift` | Modify | Add regression coverage |

### 4.2 Implementation Steps (Green Phase)
1. Add failing unit tests for missing/present plugin evidence.
2. Add pure helper to find software-instrument tracks with regions and no readable plugin evidence.
3. Emit blocker finding and let existing export readiness aggregation include it.

## 5. Edge Cases
- Software-instrument track with regions and stale mixer readback blocks.
- External MIDI tracks remain covered by the existing blocker.
- Audio tracks are not affected.

## 6. Review Checklist
- [x] Red: 테스트 실행 → FAILED 확인됨
- [x] Green: 테스트 실행 → PASSED 확인됨
- [x] Refactor: 테스트 실행 → PASSED 유지 확인됨
- [x] AC 전부 충족
- [x] 기존 테스트 깨지지 않음
- [x] 코드 스타일 준수
- [x] 불필요한 변경 없음
