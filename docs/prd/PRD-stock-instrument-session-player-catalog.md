# PRD: Stock Instrument and Session Player Intelligence Catalog (Issue #31)

**Status**: Implemented
**Date**: 2026-06-20
**Owner**: Logic Pro MCP
**Related issue**: https://github.com/MongLong0214/logic-pro-mcp/issues/31

## 1. Problem

Logic Pro MCP has stock plugin intelligence, but clients still lack a stable read-only catalog for choosing Logic stock instruments and Session Player/Drummer categories. Without a provenance-labeled catalog, agents can overclaim patch availability, direct Session Player control, or undocumented preset loading.

## 2. Goals

- Add a stable schema for Logic stock instrument and Session Player catalog entries.
- Expose read-only MCP resources for stock instrument list/detail/search and Session Player list/detail.
- Label every entry with explicit provenance, confidence, supported actions, unsupported actions, and related stock plugin IDs.
- Keep inferred and documented facts distinct.
- Make the catalog consumable by follow-up orchestration work without adding write capability.

## 3. Non-Goals

- No track creation side effects from resource reads.
- No automatic patch or preset loading.
- No direct Session Player performance/style/chord editing.
- No claim that inferred stock instruments are live-verified on the current machine.
- No third-party instrument catalog.

## 4. Schema

Every entry uses `schema: logic_pro_mcp_instrument_catalog.v1` and includes:

- `id`
- `display_name`
- `kind`
- `logic_track_type`
- `roles`
- `genre_tags`
- `known_factory_paths`
- `known_presets`
- `related_stock_plugin_ids`
- `supported_actions`
- `unsupported_actions`
- `provenance`
- `notes`

Provenance source values are `verified_live`, `filesystem_scanned`, `documented`, and `inferred`. Confidence values are `high`, `medium`, and `low`.

## 5. MCP Resources

Read-only resources:

- `logic://stock-instruments`
- `logic://stock-instruments/{id}`
- `logic://stock-instruments/search?query={query}`
- `logic://session-players`
- `logic://session-players/{id}`

## 6. Implementation Tickets

Canonical ticket board: `docs/tickets/stock-instrument-session-player-catalog/STATUS.md`

- `I31-T1`: schema, seed catalog, validation.
- `I31-T2`: MCP resource routing, public surface registration, docs.
- `I31-T3`: regression tests and verification evidence.

## 7. Acceptance Criteria

- Static catalog entries have unique stable IDs and valid schema fields.
- Provenance is explicit; documented sources carry evidence, and inferred facts are not mislabeled as verified.
- Supported and unsupported action vocabularies are strict and do not overlap.
- Related stock plugin references resolve against the stock plugin catalog.
- Resources route list/detail/search requests and reject malformed or aliased URIs.
- Public manifest, README, API docs, server catalog tests, and E2E tests advertise the same surface.
- The surface remains read-only and does not broaden any write path.

## 8. Test Plan

- Validator tests for duplicate IDs, malformed IDs, missing provenance, missing evidence, action overlap, unknown actions, and dangling references.
- Snapshot tests for stock instrument and Session Player coverage.
- Resource tests for list/detail/search and fail-closed URI handling.
- Server catalog, manifest, ResourceProvider, handler, transport, and E2E tests for public surface consistency.
- `git diff --check` and targeted `swift test --filter ...` verification.

## 9. ADR

**Decision**: ship a conservative static catalog with explicit provenance and unsupported actions.
**Drivers**: clients need planning metadata now, but current MCP write operations cannot safely control Session Player internals or guarantee arbitrary patch loading.
**Alternatives considered**: generated catalog from live Logic scans only, Markdown-only documentation, merging into `logic://stock-plugins`.
**Why chosen**: static resources are deterministic, lintable, and safe; Markdown-only guidance drifts; merging into stock plugins would blur plugin identity with musical-role planning.
**Consequences**: first version is intentionally incomplete but honest. Future live scans can upgrade provenance without changing the read API.
