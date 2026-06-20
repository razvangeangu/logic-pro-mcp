# Issue #31 Ticket Board: Stock Instrument and Session Player Intelligence Catalog

**Issue**: https://github.com/MongLong0214/logic-pro-mcp/issues/31
**PRD**: `docs/prd/PRD-stock-instrument-session-player-catalog.md`
**Status**: Implemented

## Tickets

- [x] `I31-T1` Schema, seed catalog, and validation
  - Add catalog entry/snapshot models.
  - Add stock instrument and Session Player seeds with provenance.
  - Validate IDs, provenance, action consistency, and related stock plugin references.

- [x] `I31-T2` MCP resources and public surface
  - Register `logic://stock-instruments`, `logic://stock-instruments/{id}`, `logic://stock-instruments/search?query={query}`, `logic://session-players`, and `logic://session-players/{id}`.
  - Add fail-closed URI routing.
  - Update manifest, README, and API docs to 16 resources / 10 templates.

- [x] `I31-T3` Tests and verification
  - Add unit/resource tests for catalog and routing.
  - Update server catalog, ResourceProvider, E2E, and version consistency tests.
  - Run targeted Swift tests and whitespace checks.

## Done Criteria

- Every advertised resource/template is served.
- Catalog snapshots validate with zero issues.
- Session Player capabilities remain planning-only unless an existing MCP command supports them.
- No malformed or percent-encoded route alias silently resolves.
- Verification commands pass before PR.

## Verification

Local verification on 2026-06-20:

- `swift test --filter StockInstrumentCatalog` — 15 passed.
- `swift test --filter ResourceProvider` — 11 passed.
- `swift test --filter VersionConsistency` — 7 passed.
- `swift test --filter LogicProServerHandler` — 10 passed.
- `swift test --filter LogicProServerTransport` — 18 passed.
- `swift test --filter EndToEnd` — 104 passed.
- `swift test --filter StockPluginCatalog` — 20 passed.
- `swift test --filter WorkflowSkillCatalog` — 24 passed.
- `git diff --check` — passed.
