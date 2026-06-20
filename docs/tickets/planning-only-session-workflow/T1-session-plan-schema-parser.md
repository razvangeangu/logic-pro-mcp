# I30-T1 - Session Plan Schema and Parser

**Status**: Done
**Size**: M
**PRD**: `docs/prd/PRD-planning-only-session-workflow.md`

## Goal

Create a pure session planner that turns a natural-language composition prompt into a structured, non-mutating plan.

## Scope

- Add a schema-first response contract named `logic_pro_mcp_session_plan.v1`.
- Extract tempo, key, scale, bars, genre, mood, and time signature.
- Generate deterministic section plans and chord plans.
- Suggest track roles and stock Logic instrument families.
- Report catalog availability honestly when issue #31 resources are absent.
- Surface unsupported or risky requests instead of accepting them silently.

## Acceptance Criteria

- The planner is pure and does not invoke tool dispatchers, routers, channels, or Logic.
- Prompts with explicit tempo, key, scale, bars, and genre parse deterministically.
- Prompts without tempo fall back to genre defaults.
- Minor and major chord plans are stable and tested.
- Third-party plugin names appear under `unsupported_or_risky_steps`.

## Verification

- `swift test --filter SessionPlan` - 13 tests passed.
