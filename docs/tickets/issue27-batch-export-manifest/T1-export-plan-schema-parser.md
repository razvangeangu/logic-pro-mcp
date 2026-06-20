# T1: Export Plan Schema And Parser

**PRD Ref**: PRD-batch-export-manifest-plan > US-1
**Priority**: P1 (High)
**Size**: S (< 2h)
**Status**: Done
**Depends On**: None

---

## 1. Objective
Create a pure Swift planner that builds a deterministic dry-run export manifest without touching Logic Pro.

## 2. Acceptance Criteria
- [x] AC-1: Accept explicit project path(s), absolute output root, artifact kinds, collision policy, and naming policy.
- [x] AC-2: Return schema `logic_pro_mcp_export_manifest.v1` with projects, artifacts, confirmations, baseline verification gates, and unsupported execution steps.
- [x] AC-3: Report missing project paths, unsafe output roots, unsupported artifacts, collision risks, and zero-byte artifacts honestly.

## 3. TDD Spec (Red Phase)

### 3.1 Test Cases

| # | Test Name | Type | Description | Expected |
|---|-----------|------|-------------|----------|
| 1 | `dryRunManifestPlan` | Unit | Valid project and output root produce a dry-run manifest | Planned manifest, no executed steps |
| 2 | `collisionAndZeroByteRisks` | Unit | Existing zero-byte artifact is detected | Degraded plan with overwrite and zero-byte issues |
| 3 | `rejectsInvalidParams` | Unit | Bad params fail before plan creation | `ExportPlanError` |

### 3.2 Test File Location
- `Tests/LogicProMCPTests/ProjectExportPlannerTests.swift`

### 3.3 Mock/Setup Required
- Temporary `.logicx` directories.
- Temporary output directory and zero-byte artifact.

## 4. Implementation Guide

### 4.1 Files to Modify

| File | Change Type | Description |
|------|-------------|-------------|
| `Sources/LogicProMCP/Projects/ProjectExportPlanner.swift` | Create | Planner models and param validation. |
| `Tests/LogicProMCPTests/ProjectExportPlannerTests.swift` | Create | Unit and dispatcher safety tests. |

### 4.2 Implementation Steps (Green Phase)
1. Define Codable response models and snake_case coding keys.
2. Parse project/output/artifact/collision params with fail-fast invalid shapes.
3. Build artifact paths and read filesystem metadata only.
4. Include blocked execution steps and baseline verification names.

### 4.3 Refactor Phase
- Keep live execution out of the planner so future `export_run` cannot accidentally share dry-run code paths that mutate state.

## 5. Edge Cases
- Missing projects.
- Relative output root.
- Unsupported artifact kind.
- Existing output artifact.

## 6. Review Checklist
- [x] Red: Test cases defined before final implementation.
- [x] Green: Tests passed.
- [x] Refactor: Tests still passed.
- [x] AC all met.
- [x] Existing tests not broken.
- [x] Code style followed.
- [x] No unrelated changes.
