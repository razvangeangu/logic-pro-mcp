# I31-T1: Schema, Seed Catalog, and Validation

## Scope

Add the read-only catalog model for stock instruments and Session Players.

## Acceptance

- Entry schema is stable as `logic_pro_mcp_instrument_catalog.v1`.
- ID namespace is restricted to `logic.stock.instrument.*` and `logic.session_player.*`.
- Provenance sources are explicit and documented sources require evidence.
- Supported and unsupported action lists cannot overlap.
- Related stock plugin IDs resolve.

## Result

Implemented in `StockInstrumentCatalog.swift` with validator coverage in `StockInstrumentCatalogTests.swift`.
