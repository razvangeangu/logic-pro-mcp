# PRD: Batch Export Manifest Plan

**Version**: 0.1
**Author**: Codex
**Date**: 2026-06-20
**Status**: Done
**Size**: S

---

## 1. Problem Statement

### 1.1 Background
Issue #27 asks for batch bounce/stem/export workflows, but live execution is blocked until the project can prove safe open/bounce/close boundaries and post-export verification. The first reviewable scope is a deterministic plan contract that clients can inspect before any Logic project mutation.

### 1.2 Problem Definition
Agents need a dry-run export manifest that names target projects, expected artifacts, collision risks, required confirmations, and unsupported execution steps without opening Logic Pro or writing files.

### 1.3 Impact of Not Solving
Without a plan contract, any future batch export implementation would either over-claim unsupported live behavior or duplicate path/collision/verification logic across clients.

## 2. Goals & Non-Goals

### 2.1 Goals
- [x] G1: Add `logic_project export_plan` returning JSON schema `logic_pro_mcp_export_manifest.v1`.
- [x] G2: Keep the command read-only: no ChannelRouter call, no Logic open/bounce/close, no manifest/audio writes.
- [x] G3: Report baseline verification gates and blocked future execution steps.

### 2.2 Non-Goals
- NG1: No live batch bounce, stem export, resume, or queue runner in this PR.
- NG2: No cloud upload, email delivery, or external sharing.
- NG3: No #29 audio analysis execution from the dry-run planner.

## 3. User Stories & Acceptance Criteria

### US-1: Dry-run export planning
**As a** client, **I want** a structured export plan, **so that** I can review paths and safety gates before any Logic mutation.

**Acceptance Criteria:**
- [x] AC-1.1: Given absolute `.logicx` project paths and an absolute output root, when `logic_project export_plan` is called, then JSON includes schema, run id, projects, expected artifacts, confirmations, and blocked steps.
- [x] AC-1.2: Given existing artifact paths, when collision policy is `fail_if_exists`, then the response reports overwrite and zero-byte risks without modifying the file.
- [x] AC-1.3: Given invalid parameter shapes, when the planner runs, then it returns `invalid_params` and routes no channels.

### US-2: Workflow discovery
**As a** workflow-skill consumer, **I want** a catalog entry for export planning, **so that** I can discover the safe first step without confusing it with live export execution.

**Acceptance Criteria:**
- [x] AC-2.1: The workflow catalog includes `logic.workflow.export.batch_plan`.
- [x] AC-2.2: The workflow is `read_only`, deterministic, and production-ready only for planning.
- [x] AC-2.3: Limitations explicitly say the workflow does not open Logic, bounce, resume, or write manifests.

## 4. Technical Design

### 4.1 Architecture Overview
`ProjectExportPlanner` is a pure planning component used directly by `ProjectDispatcher` for the `export_plan` command. It reads only filesystem metadata for declared output artifacts and never calls `ChannelRouter`.

### 4.2 Data Model Changes
No persisted schema changes. The response model is a Codable JSON envelope:
- `ProjectExportPlan`
- `ProjectExportPlanProject`
- `ProjectExportPlanArtifact`
- `ProjectExportArtifactVerification`
- `ProjectExportWorkflowStep`
- `ProjectExportConfirmation`
- `ProjectExportBlockedStep`

### 4.3 API Design

| Method | Endpoint | Description | Auth |
|--------|----------|-------------|------|
| MCP tool | `logic_project export_plan` | Build a dry-run batch export manifest plan | MCP client |

Params:
- `projects?: string[]`
- `project?: string` or `path?: string`
- `output_root: string`
- `artifacts?: string[]` where values are `bounce`, `stem`, `preview`, `variant`
- `collision_policy?: "fail_if_exists" | "skip_existing"`
- `naming_policy?: string`

### 4.4 Key Technical Decisions

| Decision | Options Considered | Chosen | Rationale |
|----------|--------------------|--------|-----------|
| Execution boundary | Add live `export_run` now vs dry-run first | Dry-run first | Issue #27 remains blocked for live execution evidence; planning is safe and reviewable. |
| Routing | Reuse `ChannelRouter` vs direct planner | Direct planner | The command must prove no Logic open/bounce/close can occur. |
| Artifact checks | Ignore output state vs read metadata | Read metadata only | Collision and zero-byte evidence are useful and non-mutating. |

## 5. Edge Cases & Error Handling

| # | Scenario | Expected Behavior | Severity |
|---|----------|-------------------|----------|
| E1 | Missing project list/path | `invalid_params` before plan creation | P1 |
| E2 | Relative output root | `invalid_params` before plan creation | P1 |
| E3 | Unsupported artifact kind | `invalid_params` before plan creation | P1 |
| E4 | Project path missing | Plan status `degraded`, project validation issue included | P2 |
| E5 | Existing artifact under fail-if-exists | Plan status `degraded`, artifact overwrite issue included | P2 |

## 6. Security & Permissions

N/A for S scope. The command is read-only and does not request new OS permissions.

## 7. Performance & Monitoring

N/A for S scope. Runtime is proportional to declared project/artifact count and uses local filesystem metadata reads.

## 8. Testing Strategy

### 8.1 Unit Tests
- `ProjectExportPlannerTests`: manifest shape, blocked steps, collision/zero-byte detection, invalid params.

### 8.2 Integration Tests
- `ProjectExportPlannerTests`: dispatcher response JSON and no channel routing.
- `WorkflowSkillCatalogTests`: workflow catalog validation, command census, workflow search.
- `EndToEndTests`: server tool call returns dry-run manifest.

### 8.3 Edge Case Tests
- Relative output root.
- Unsupported artifact kind.
- Empty projects array.
- Existing zero-byte output artifact.

## 9. Rollout Plan

N/A for S scope. This is a new command and workflow entry with no migration.

## 10. Dependencies & Risks

### 10.1 Dependencies

| Dependency | Owner | Status | Risk if Delayed |
|------------|-------|--------|-----------------|
| Issue #29 audio analysis | Project | PR #94 open | Live export verification remains incomplete. |
| Live export evidence for #27 | Project | Blocked | `export_run` and `export_resume` must stay unavailable. |

### 10.2 Risks

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Clients treat plan as execution | Medium | High | Response uses `execution_mode: dry_run_only` and lists unsupported steps. |
| Future live exporter diverges from plan schema | Medium | Medium | Schema and tests define the first manifest contract. |
