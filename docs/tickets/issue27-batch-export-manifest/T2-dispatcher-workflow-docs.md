# T2: Dispatcher, Workflow Catalog, And Docs

**PRD Ref**: PRD-batch-export-manifest-plan > US-1, US-2
**Priority**: P1 (High)
**Size**: S (< 2h)
**Status**: Done
**Depends On**: T1

---

## 1. Objective
Expose the planner through the public MCP surface and workflow catalog while documenting the dry-run-only boundary.

## 2. Acceptance Criteria
- [x] AC-1: `logic_project export_plan` returns compact JSON from `ProjectExportPlanner`.
- [x] AC-2: The dispatcher does not route any channels for `export_plan`.
- [x] AC-3: Workflow catalog includes `logic.workflow.export.batch_plan` as read-only deterministic planning.
- [x] AC-4: README, API docs, and system help mention `export_plan`.

## 3. TDD Spec (Red Phase)

### 3.1 Test Cases

| # | Test Name | Type | Description | Expected |
|---|-----------|------|-------------|----------|
| 1 | `dispatcherDoesNotRoute` | Integration | Dispatcher returns JSON and records no channel ops | No `MockChannel` operations |
| 2 | `defaultPackValidates` | Unit | Workflow catalog validates after new workflow | Valid pack |
| 3 | `workflowResources` | Integration | Workflow search finds export plan workflow | Search result includes workflow |

### 3.2 Test File Location
- `Tests/LogicProMCPTests/ProjectExportPlannerTests.swift`
- `Tests/LogicProMCPTests/WorkflowSkillCatalogTests.swift`

### 3.3 Mock/Setup Required
- `MockChannel` registered with `ChannelRouter` for no-route assertion.
- Workflow resource reads via `ResourceHandlers`.

## 4. Implementation Guide

### 4.1 Files to Modify

| File | Change Type | Description |
|------|-------------|-------------|
| `Sources/LogicProMCP/Dispatchers/ProjectDispatcher.swift` | Modify | Add `export_plan` command case and metadata. |
| `Sources/LogicProMCP/Workflows/WorkflowSkillCatalog.swift` | Modify | Add command census and workflow skill. |
| `Sources/LogicProMCP/Dispatchers/SystemDispatcher.swift` | Modify | Add help text. |
| `README.md` | Modify | Mention export plan in project lifecycle row. |
| `docs/API.md` | Modify | Document command params/return/channel/level. |

### 4.2 Implementation Steps (Green Phase)
1. Add dispatcher command case before mutating lifecycle commands.
2. Add command census entry so linter can validate workflow steps.
3. Add read-only workflow with explicit limitations.
4. Update docs and help text.

### 4.3 Refactor Phase
- Keep the workflow step `mutates: false` and limitations explicit to avoid production mutation claims.

## 5. Edge Cases
- Unknown command list must include `export_plan`.
- Workflow linter must not require confirmations for the read-only planner.

## 6. Review Checklist
- [x] Red: Test cases defined before final implementation.
- [x] Green: Tests passed.
- [x] Refactor: Tests still passed.
- [x] AC all met.
- [x] Existing tests not broken.
- [x] Code style followed.
- [x] No unrelated changes.
