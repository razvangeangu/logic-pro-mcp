# PRD: Setup Lifecycle Doctor Foundation

**Version**: 0.1
**Author**: Codex
**Date**: 2026-06-20
**Status**: Done
**Size**: M

---

## 1. Problem Statement

### 1.1 Background
Issue #26 identifies setup lifecycle as the highest-priority adoption blocker. The first safe PR scope is a read-only `doctor --json` foundation with stable check IDs and docs remediation anchors.

### 1.2 Problem Definition
Users need a non-mutating command that explains whether the binary, MCP registration, permissions, Logic readiness, and manual-validation setup are healthy.

### 1.3 Impact of Not Solving
Users must infer setup state from scripts and source code, increasing support burden and time-to-first-success.

## 2. Goals & Non-Goals

### 2.1 Goals
- [x] G1: Add `LogicProMCP doctor` and `LogicProMCP doctor --json`.
- [x] G2: Emit `logic_pro_mcp_doctor.v1` with stable check IDs.
- [x] G3: Provide actionable remediation for every non-pass state.
- [x] G4: Add docs anchors for every check ID.

### 2.2 Non-Goals
- NG1: Full install/update/uninstall binary command surface.
- NG2: Mutating repair actions from doctor.
- NG3: Closing #26 in one PR.

## 3. User Stories & Acceptance Criteria

### US-1: Read Setup State
**As a** user, **I want** `doctor --json`, **so that** I can diagnose setup without mutating my machine.

**Acceptance Criteria:**
- [x] AC-1.1: `doctor --json` returns `schema: "logic_pro_mcp_doctor.v1"`.
- [x] AC-1.2: Doctor does not start the MCP server.
- [x] AC-1.3: Every non-pass check includes remediation.

### US-2: Follow Stable Remediation
**As a** support or MCP client author, **I want** stable check IDs and docs anchors, **so that** failures link to exact fixes.

**Acceptance Criteria:**
- [x] AC-2.1: Check IDs are stable and covered by tests.
- [x] AC-2.2: Docs contain an anchor for every doctor check ID.

## 4. Technical Design

### 4.1 Architecture Overview
Add `SetupDoctor` as a pure/read-only utility used by `MainEntrypoint` before server startup. The doctor runtime is injectable for deterministic tests.

### 4.2 Data Model Changes
N/A

### 4.3 API Design

| Method | Endpoint | Description | Auth |
|--------|----------|-------------|------|
| CLI | `LogicProMCP doctor` | Human-readable setup doctor | Local process |
| CLI | `LogicProMCP doctor --json` | Stable JSON setup doctor | Local process |

### 4.4 Key Technical Decisions

| Decision | Options Considered | Chosen | Rationale |
|----------|-------------------|--------|-----------|
| Startup isolation | Reuse system health vs standalone doctor | Standalone doctor | `doctor` must not start channels, pollers, or mutate state. |
| Remediation | Free text only vs stable docs anchors | Stable anchors | Enables support links and schema tests. |

## 5. Edge Cases & Error Handling

| # | Scenario | Expected Behavior | Severity |
|---|----------|-------------------|----------|
| E1 | Binary path missing | `binary.path` fails with docs remediation | High |
| E2 | Logic not running | Automation is manual/not-verifiable, not falsely failed as installed-broken | Medium |
| E3 | Claude CLI missing | Registration check becomes manual with explicit registration command/docs | Medium |

## 8. Testing Strategy

### 8.1 Unit Tests
Doctor schema, check ID ordering, status aggregation, main entrypoint no-server-start behavior, docs anchor coverage.

### 8.2 Integration Tests
Existing installer fail-closed tests remain in place.

### 8.3 Edge Case Tests
Missing binary, missing permissions, no approvals, missing command probes.
