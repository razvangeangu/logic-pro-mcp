# PRD: Project Session Audit And Cleanup Plan

**Issue**: #28 Project/session audit and cleanup plan workflow
**Status**: Approved / Implemented
**Date**: 2026-06-20
**Size**: M

## Problem

Messy Logic Pro sessions need inspection before mutation. A client should be able to ask what is known, what is stale or risky, and what cleanup steps might be safe later without letting an agent silently reorganize a project.

## Goals

- Add read-only audit output with schema `logic_pro_mcp_project_audit.v1`.
- Add read-only cleanup-plan output with schema `logic_pro_mcp_project_cleanup_plan.v1`.
- Include evidence and provenance for project, transport, tracks, regions, markers, mixer, plugins, and export readiness.
- Generate deterministic findings for ambiguity, stale readback, duplicate/placeholder names, empty tracks, solo/arm states, marker gaps, mixer freshness, and occupied plugin slots.
- Ensure cleanup plan steps include target, operation, rationale, risk, confirmation, expected readback, recovery, stop condition, support status, and mutation flag.
- Register resource and tool-command surfaces plus a workflow skill.

## Non-Goals

- No cleanup execution in this milestone.
- No deletion by default.
- No subjective audio-quality, mix-quality, or musical-intent claims.
- No project-alternative diffing.
- No stem/export execution; that remains related to #27.

## Acceptance Criteria

- `logic://project/audit` and `logic_project audit` return audit JSON without mutating Logic Pro.
- `logic://project/cleanup-plan` and `logic_project cleanup_plan` return serializable cleanup steps without mutating Logic Pro.
- Findings are deterministic and covered by unit tests.
- Unsupported or unsafe cleanup actions are labelled `supported_by_current_tools:false`.
- Public catalog, manifest, README, API docs, and workflow skill catalog reflect the new read-only surfaces.

## Verification

- `swift test --filter ProjectSessionAudit`
- `swift test --filter ResourceProvider`
- `swift test --filter VersionConsistency`
- `swift test --filter LogicProServerHandler`
- `swift test --filter LogicProServerTransport`
- `swift test --filter WorkflowSkillCatalog`
- `swift test --filter EndToEnd`
