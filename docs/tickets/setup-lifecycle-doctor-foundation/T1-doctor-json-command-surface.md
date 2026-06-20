# T1: Doctor JSON Command Surface

**PRD Ref**: PRD-setup-lifecycle-doctor-foundation > US-1
**Priority**: P1 (High)
**Size**: M (2-4h)
**Status**: Done
**Depends On**: None

---

## 1. Objective
Add a read-only `LogicProMCP doctor` / `doctor --json` CLI path that executes before server startup.

## 2. Acceptance Criteria
- [x] AC-1: `doctor --json` returns `logic_pro_mcp_doctor.v1`.
- [x] AC-2: Doctor does not start the server.
- [x] AC-3: Stable check IDs cover binary, install source, release, MCP registration, permissions, Logic state, and manual-validation channels.

## 3. TDD Spec (Red Phase)

### 3.1 Test Cases

| # | Test Name | Type | Description | Expected |
|---|-----------|------|-------------|----------|
| 1 | `testSetupDoctorJSONContractStableCheckIDsAndOKAggregation` | Unit | Stable schema and check order | PASS after implementation |
| 2 | `testMainEntrypointDoctorJSONDoesNotStartServerAndWritesStdout` | Unit | CLI route does not create/start server | PASS after implementation |
| 3 | `testSetupDoctorReportsActionableRemediationForNonPassStates` | Unit | Non-pass checks have remediation | PASS after implementation |

### 3.2 Test File Location
- `Tests/LogicProMCPTests/SetupDoctorTests.swift`

### 3.3 Mock/Setup Required
- Injectable `SetupDoctor.Runtime`
- Temporary `ManualValidationStore`

## 4. Implementation Guide

### 4.1 Files to Modify
| File | Change Type | Description |
|------|-------------|-------------|
| `Sources/LogicProMCP/Utilities/SetupDoctor.swift` | Create | Doctor report model and read-only probes |
| `Sources/LogicProMCP/MainEntrypoint.swift` | Modify | Route `doctor` before server startup |
| `Sources/LogicProMCP/main.swift` | Modify | Add stdout injection passthrough |

### 4.2 Implementation Steps (Green Phase)
1. Add doctor report model and aggregation.
2. Add read-only runtime probes with test injection.
3. Route CLI command before approval mutations and server startup.

### 4.3 Refactor Phase
- Keep remediation values centralized in `SetupDoctor.remediationAnchorsByCheckID`.

## 5. Edge Cases
- Missing binary path
- Missing executable bit
- Missing Claude CLI
- Logic not running
- Missing manual-validation approvals

## 6. Review Checklist
- [x] Red: tests specified before implementation
- [x] Green: targeted tests pass
- [x] Refactor: doctor remains isolated from server startup
- [x] AC 전부 충족
- [x] 기존 테스트 깨지지 않음
- [x] 코드 스타일 준수
- [x] 불필요한 변경 없음
