# PRD: Planning-Only Composition Session Workflow (Issue #30)

**Status**: Implemented
**Date**: 2026-06-20
**Owner**: Logic Pro MCP
**Related issue**: https://github.com/MongLong0214/logic-pro-mcp/issues/30

## 1. Problem

Clients need a safe way to turn a natural-language composition request into a structured Logic session plan before any DAW mutation occurs. Prompt-only guidance is hard to validate and can imply unsafe autonomy such as creating tracks, importing MIDI, or loading instruments without confirmation.

## 2. Goals

- Expose a deterministic, read-only session plan resource.
- Parse prompt intent for tempo, key, scale, genre, mood, bars, and time signature.
- Generate arrangement sections, a chord plan, track suggestions, workflow steps, unsupported steps, confirmations, and the next safe action.
- Report proposed mutating operations as not executed and confirmation-gated.
- Degrade honestly when the stock instrument catalog from issue #31 is not available.
- Validate the plan against the current public Logic Pro MCP command/resource surface.

## 3. Non-Goals

- No project creation, track creation, MIDI import, preset loading, playback, recording, bounce, or Logic mutation.
- No background invocation of MCP tools from the planning resource.
- No third-party plugin availability claims.
- No attempt to replace human musical judgment.

## 4. Public Surface

Read-only resource template:

- `logic://workflow-plans/session?prompt={prompt}`

Workflow skill:

- `logic.workflow.composition.session_plan`

Plan schema:

- `logic_pro_mcp_session_plan.v1`

## 5. Output Contract

The plan includes:

- `schema`
- `prompt`
- `status`
- `parsed_intent`
- `instrument_catalog_status`
- `sections`
- `chord_plan`
- `track_plan`
- `workflow_steps`
- `unsupported_or_risky_steps`
- `required_confirmations`
- `tool_surface_validation`
- `next_safe_action`
- `provenance`

## 6. Safety Contract

- Resource reads must be side-effect free.
- Mutating workflow steps must have `executed: false`.
- Mutating workflow steps must name a public command and require explicit confirmation.
- Unsupported or risky requests must be surfaced instead of silently accepted.
- URI routing must fail closed for malformed paths, duplicate or missing prompt params, fragments, and encoded path aliases.

## 7. Implementation Tickets

Canonical ticket board: `docs/tickets/planning-only-session-workflow/STATUS.md`

- `I30-T1`: session plan schema, parser, and generator.
- `I30-T2`: resource route, workflow skill, manifest, and docs.
- `I30-T3`: targeted tests and verification evidence.

## 8. Acceptance Criteria

- A valid resource read returns `schema: logic_pro_mcp_session_plan.v1`.
- Tempo, key, scale, bars, genre, and time signature extraction are covered by tests.
- Section and chord generation are deterministic for supported prompts.
- Track planning reports degraded catalog status before issue #31 resources are available.
- All proposed mutating steps are non-executed and confirmation-gated.
- Unsupported third-party plugin requests are reported.
- Resource routing rejects malformed or ambiguous URIs.
- Public docs and manifest resource-template counts remain consistent.

## 9. Test Plan

- Unit tests for intent parsing, section generation, chord generation, track planning, unsupported-step reporting, and dry-run safety.
- Resource tests for schema output and fail-closed URI routing.
- Workflow catalog tests for public surface validation.
- Server handler, transport, version consistency, and E2E tests for advertised resource/template surface.

## 10. ADR

**Decision**: ship session planning as a read-only resource plus workflow skill, not an executor.

**Drivers**: preserve Logic mutation safety, make plans machine-readable, and keep clients honest about which steps are merely proposed.

**Alternatives considered**: markdown-only prompt recipe, autonomous session builder, or a mutating tool that creates tracks directly.

**Why chosen**: markdown-only output is not strongly validated; autonomous building violates the safety boundary; a read-only resource gives clients useful structure without side effects.

**Consequences**: the first safe next action is to review the plan and choose a confirmed workflow step. Actual execution remains outside this resource.
