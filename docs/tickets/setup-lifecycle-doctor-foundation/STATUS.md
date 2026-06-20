# Pipeline Status: Setup Lifecycle Doctor Foundation

**PRD**: docs/prd/PRD-setup-lifecycle-doctor-foundation.md
**Size**: M
**Current Phase**: 7

## Ticket Status 정의
- **Todo**: 미착수
- **In Progress**: 구현 중
- **In Review**: 리뷰 진행 중
- **Done**: 완료 (AC 충족 + 테스트 PASS)
- **Invalidated**: 역행으로 무효화됨

## Tickets

| Ticket | Title | Status | Review | Notes |
|--------|-------|--------|--------|-------|
| T1 | Doctor JSON command surface | Done | PASS | Red/green covered by SetupDoctorTests |
| T2 | Remediation docs anchors | Done | PASS | Docs anchor coverage test added |

## Review History

| Phase | Round | Verdict | P0 | P1 | P2 | Notes |
|-------|-------|---------|----|----|----|-------|
| 2 | 1 | ALL PASS | 0 | 0 | 0 | Orchestrator review, #26 scoped to doctor foundation |
| 4 | 1 | ALL PASS | 0 | 0 | 0 | TDD specs map to issue acceptance criteria |
| 6 | 1 | ALL PASS | 0 | 0 | 0 | BOOMER-6 self-review: no mutation path in doctor |
