# PRD: Issue 60 Locale-Agnostic UI Policy Foundation

**Version**: 0.1
**Author**: Codex
**Date**: 2026-06-20
**Status**: Done
**Size**: M

---

## 1. Problem Statement

### 1.1 Background
Issue #60 is an epic to make Logic UI automation fully locale-agnostic. The full epic cannot be closed by one PR because the repository still contains many historical AX and AppleScript label matchers. A safe first PR should harden the touched surfaces and establish a central policy for unavoidable localized labels.

### 1.2 Problem Definition
Touched AX code paths used English/Korean labels inline, which made fallback behavior hard to audit and easy to expand without readback evidence. The first policy PR needs to move those labels behind a single source of truth and document that labels are compatibility hints, not proof of success.

### 1.3 Impact of Not Solving
Locale-specific ad hoc matching can silently regress non-English Logic UI sessions, make reviews miss unsafe matchers, and weaken the project's State A readback contract.

## 2. Goals & Non-Goals

### 2.1 Goals
- [x] G1: Add a central `AXLocalePolicy` for touched AX localized labels and menu path helpers.
- [x] G2: Move verified-plugin, dialog cleanup, Save/Cancel, and plugin-format label matching in touched paths to the policy.
- [x] G3: Add deterministic tests for English/Korean policy behavior.
- [x] G4: Document that localized labels are fallback hints and mutating paths still require readback.

### 2.2 Non-Goals
- NG1: Do not claim the entire #60 epic is complete.
- NG2: Do not migrate every historical AX or AppleScript label matcher in this PR.
- NG3: Do not add new live UI automation behavior.

## 3. User Stories & Acceptance Criteria

### US-1: Central locale policy
**As a** maintainer, **I want** touched localized AX labels to live in one policy module, **so that** future review can see and constrain locale assumptions.

**Acceptance Criteria:**
- [x] AC-1.1: Given touched AX menu/dialog code, when it needs English/Korean labels, then it reads them from `AXLocalePolicy`.
- [x] AC-1.2: Given policy tests, when English/Korean variants are checked, then expected labels and menu paths match.
- [x] AC-1.3: Given mutating UI paths, when label fallback is used, then success is still gated by existing readback behavior.

### US-2: Epic-safe scope
**As a** reviewer, **I want** the PR to state remaining #60 work, **so that** this policy foundation is not mistaken for closing the epic.

**Acceptance Criteria:**
- [x] AC-2.1: Ticket status lists remaining audit/migration/live-verification work.
- [x] AC-2.2: PR body references #60 without closing it.

## 4. Technical Design

### 4.1 Architecture Overview
`AXLocalePolicy` centralizes label sets and helper behavior for the touched AX paths. Callers keep their existing control flow and readback gates, but stop carrying scattered label arrays inline.

### 4.2 Data Model Changes
No persisted data model changes.

### 4.3 API Design
No public MCP API change.

### 4.4 Key Technical Decisions

| Decision | Options Considered | Chosen | Rationale |
|----------|--------------------|--------|-----------|
| Scope | Full epic migration vs touched-surface foundation | Touched-surface foundation | #60 is an epic; a focused PR is reviewable and safer. |
| Evidence | Treat labels as success evidence vs compatibility hints | Compatibility hints | Project policy requires State A readback for successful mutation claims. |
| Placement | Inline arrays vs central policy | Central policy | Makes locale assumptions auditable. |

## 5. Edge Cases & Error Handling

| # | Scenario | Expected Behavior | Severity |
|---|----------|-------------------|----------|
| E1 | Unknown locale label | Existing fail-closed behavior remains; no success without readback | P1 |
| E2 | Dialog cleanup label differs | Policy can be extended in one place after evidence | P2 |
| E3 | Untouched matcher remains inline | Listed as remaining epic work, not hidden by this PR | P2 |

## 8. Testing Strategy

### 8.1 Unit Tests
- `AXLocalePolicy` deterministic policy tests.

### 8.2 Integration Tests
- Existing AX element, verified plugin insert, accessibility channel, and inventory tests cover touched call paths.

### 8.3 Edge Case Tests
- English and Korean labels.
- Mutating path readback-gated behavior remains covered by existing plugin tests.

## 10. Dependencies & Risks

### 10.1 Dependencies

| Dependency | Owner | Status | Risk if Delayed |
|------------|-------|--------|-----------------|
| Full AX matcher audit | Project | Remaining epic work | #60 cannot be closed yet. |
| English/Korean live verification notes | Project | Remaining epic work | Policy confidence remains deterministic until live notes land. |

### 10.2 Risks

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Reviewers mistake this for full epic completion | Medium | Medium | STATUS and PR body state partial scope. |
| Central policy grows without evidence | Medium | High | Documentation says labels are hints, not success evidence. |
