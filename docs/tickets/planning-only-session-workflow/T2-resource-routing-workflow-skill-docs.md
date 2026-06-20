# I30-T2 - Resource Routing, Workflow Skill, and Docs

**Status**: Done
**Size**: M
**PRD**: `docs/prd/PRD-planning-only-session-workflow.md`

## Goal

Expose the session planner through read-only public surfaces and keep the documented catalog in sync.

## Scope

- Register `logic://workflow-plans/session?prompt={prompt}` as a resource template.
- Route only the exact `/session` workflow-plan path.
- Reject fragments, missing prompts, duplicate prompt params, encoded path aliases, and malformed percent escapes.
- Add `logic.workflow.composition.session_plan` to the workflow skill catalog.
- Update manifest, README, API docs, system help, and server catalog counts.

## Acceptance Criteria

- Resource reads return a JSON session plan with `schema: logic_pro_mcp_session_plan.v1`.
- The route is read-only and side-effect free.
- Workflow skill references only valid public resource/tool names.
- Public docs and manifest agree on 14 static resources and 8 resource templates.

## Verification

- `swift test --filter WorkflowSkillCatalog` - 24 tests passed.
- `swift test --filter ResourceProvider` - 11 tests passed.
- `swift test --filter LogicProServerHandler` - 10 tests passed.
- `swift test --filter LogicProServerTransport` - 18 tests passed.
- `swift test --filter VersionConsistency` - 7 tests passed.
