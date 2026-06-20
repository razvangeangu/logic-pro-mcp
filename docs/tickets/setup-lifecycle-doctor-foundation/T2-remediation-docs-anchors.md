# T2: Remediation Docs Anchors

**PRD Ref**: PRD-setup-lifecycle-doctor-foundation > US-2
**Priority**: P1 (High)
**Size**: S (< 2h)
**Status**: Done
**Depends On**: T1

---

## 1. Objective
Document exact remediation anchors for every stable doctor check ID.

## 2. Acceptance Criteria
- [x] AC-1: Every doctor check ID has a docs anchor.
- [x] AC-2: Docs include commands or manual System Settings paths for non-pass states.
- [x] AC-3: Anchor coverage is enforced by test.

## 3. TDD Spec (Red Phase)

### 3.1 Test Cases

| # | Test Name | Type | Description | Expected |
|---|-----------|------|-------------|----------|
| 1 | `testSetupDocsContainEveryDoctorRemediationAnchor` | Unit/docs | Check every configured anchor exists in docs/SETUP.md | PASS after docs update |
| 2 | `testMainEntrypointDoctorHumanOutputIncludesStableIDs` | Unit | Human output exposes stable IDs | PASS after implementation |

### 3.2 Test File Location
- `Tests/LogicProMCPTests/SetupDoctorTests.swift`

### 3.3 Mock/Setup Required
- None beyond local docs file read.

## 4. Implementation Guide

### 4.1 Files to Modify
| File | Change Type | Description |
|------|-------------|-------------|
| `docs/SETUP.md` | Modify | Add setup doctor section and remediation anchors |
| `Tests/LogicProMCPTests/SetupDoctorTests.swift` | Modify | Add docs coverage test |

### 4.2 Implementation Steps (Green Phase)
1. Add `Setup Doctor` section.
2. Add explicit HTML anchors so links are stable.
3. Add test linking every configured anchor to docs.

### 4.3 Refactor Phase
- Keep docs anchor names aligned with check IDs.

## 5. Edge Cases
- Markdown-generated anchors may drift; use explicit HTML `id` attributes instead.

## 6. Review Checklist
- [x] Red: docs anchor coverage test specified
- [x] Green: docs coverage passes
- [x] Refactor: anchors centralized in code
- [x] AC 전부 충족
- [x] 기존 테스트 깨지지 않음
- [x] 코드 스타일 준수
- [x] 불필요한 변경 없음
