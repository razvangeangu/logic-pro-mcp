# T3: Workflow Docs Tests

**Status**: Done
**Issue**: #28

## Scope

Register the workflow skill and update public surface documentation/tests.

## Acceptance Criteria

- Workflow `logic.workflow.project.audit_cleanup_plan` is read-only, production-ready, and dependency-resolved.
- Manifest, README, API docs, and version consistency tests show 16 static resources.
- E2E catalog tests advertise the new resources.

## Verification

- `swift test --filter VersionConsistency`
- `swift test --filter WorkflowSkillCatalog`
- `swift test --filter EndToEnd`
