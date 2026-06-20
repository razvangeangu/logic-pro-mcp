# T3: Tests And Verification

**PRD Ref**: PRD-batch-export-manifest-plan > US-1, US-2
**Priority**: P1 (High)
**Size**: S (< 2h)
**Status**: Done
**Depends On**: T1, T2

---

## 1. Objective
Verify the planner, dispatcher, workflow catalog, server E2E, and docs consistency for the new dry-run command.

## 2. Acceptance Criteria
- [x] AC-1: Planner tests cover manifest shape, invalid params, collision risk, and no-route dispatcher behavior.
- [x] AC-2: Workflow catalog tests cover command census and workflow discoverability.
- [x] AC-3: E2E server call returns `dry_run_only` manifest JSON.
- [x] AC-4: Handler, transport, and version consistency filters continue passing.

## 3. TDD Spec (Red Phase)

### 3.1 Test Cases

| # | Test Name | Type | Description | Expected |
|---|-----------|------|-------------|----------|
| 1 | `testE2EProjectExportPlanReturnsDryRunManifest` | E2E | Server handler dispatches command and returns manifest | `dry_run_only`, no executed workflow steps |
| 2 | `defaultPackCommandsAreReal` | Unit | Catalog commands match dispatcher cases | `export_plan` has executable dispatcher case |
| 3 | `testReadmeAndAPIDocsMatchPublicSurfaceAndRouting` | Docs regression | Public docs remain consistent | Pass |

### 3.2 Test File Location
- `Tests/LogicProMCPTests/EndToEndTests.swift`
- `Tests/LogicProMCPTests/WorkflowSkillCatalogTests.swift`
- `Tests/LogicProMCPTests/VersionConsistencyTests.swift`

### 3.3 Mock/Setup Required
- Temporary project/output folders for E2E call.

## 4. Implementation Guide

### 4.1 Files to Modify

| File | Change Type | Description |
|------|-------------|-------------|
| `Tests/LogicProMCPTests/EndToEndTests.swift` | Modify | Add dry-run manifest server test. |
| `Tests/LogicProMCPTests/WorkflowSkillCatalogTests.swift` | Modify | Add workflow assertions/search coverage. |
| `Tests/LogicProMCPTests/DispatcherTests.swift` | Modify | Assert tool metadata documents `export_plan`. |

### 4.2 Implementation Steps (Green Phase)
1. Run planner-specific tests.
2. Run workflow catalog and dispatcher filters.
3. Run E2E, handler, transport, and version consistency filters.
4. Run whitespace checks before commit.

### 4.3 Refactor Phase
- Keep tests focused on dry-run behavior and avoid introducing live Logic requirements.

## 5. Edge Cases
- Server E2E must not require Logic Pro to be running.
- The workflow search result must be discoverable by export intent.

## 6. Review Checklist
- [x] Red: Test cases defined before final implementation.
- [x] Green: Tests passed.
- [x] Refactor: Tests still passed.
- [x] AC all met.
- [x] Existing tests not broken.
- [x] Code style followed.
- [x] No unrelated changes.
