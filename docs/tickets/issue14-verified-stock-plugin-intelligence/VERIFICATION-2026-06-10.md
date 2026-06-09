# Verification Evidence - Issue #14 Hardening Round (2026-06-10)

Date: 2026-06-10 KST
Branch: `feature/issue-14-stock-plugin-intelligence`
Scope: post-review hardening of the stock plugin intelligence surface, Logic Pro 12.2 host.

## Review Inputs

- Adversarial review: Codex gpt-5.5 (`model_reasoning_effort=xhigh`), verdict on the pre-hardening branch: FAIL (3 P1 / 4 P2).
- Cross-check: 2026-06-08/09 full-repo enterprise review (release identity, Honest Contract globalization).
- Machine evidence motivating R1: `/Applications/Logic Pro.app/Contents/Resources/Plug-In Settings/SilverVerb` exists on this Logic 12.2 install, while the pre-hardening catalog shipped SilverVerb as `unavailable` with fabricated `absence_checked` evidence.

## Findings → Fixes

| Finding (severity) | Fix |
|---|---|
| `manifested` overclaimed from app presence (P1) | Per-plugin factory `Plug-In Settings/<Display Name>` folder probe (app bundle root + `/Library/Application Support/Logic`); probed `source_path` recorded in provenance; no folder → stays `inferred`. |
| `unavailable` claimed an absence check that never ran (P1) | Fabricated entry removed. `unavailable` is only producible via census `unavailablePluginIDs` (live census / fixtures). Folder absence is explicitly not treated as evidence of absence. |
| Release identity unchanged under grown surface (P1) | Documented contract: merge ⇒ next release must be `v3.5.0`; no rebuild as `3.4.6`. Packaging surfaces intentionally untouched on branch (they pin published v3.4.6 artifacts). |
| `verified`/`observed` dead and untested (P2) | Census ID-set overlay implemented end-to-end and unit-tested per state. |
| `readback_mismatch` not producible (P2) | `readbackMismatchPluginIDs` census set + provenance factory + validator evidence rule + tests. |
| Tests not deterministic (P2) | Unit assertions pinned to `StockPluginCensus.deterministic()`; production snapshot covered by a host-independent conservativeness invariant (`states ⊆ {inferred, manifested}`). |
| URI routing accepted malformed URIs; query double-decoded (P2) | `URLComponents`-based exact routing; unknown subpaths/params fail closed; single-decode regression test (`a%252Bb` → `a%2Bb`). |

Additional hardening: catalog expanded to 103 documented stock entries; validator extended (id format, value ranges, duplicate parameter IDs, preset provenance, mismatch evidence); `insert_only` capability pinned to the `insert_plugin` allowlist by test; shared JSON helpers extracted to `ResourceJSONHelpers.swift` to remove the #14/#15 duplicate-helper merge hazard.

## Deterministic Gates

| Gate | Result | Evidence |
|---|---:|---|
| Format check | PASS | `git diff --check` exit 0. |
| Stock plugin suites | PASS | `swift test --no-parallel --filter StockPlugin` → 17 tests passed. |
| Full test suite | PASS | `swift test --no-parallel` → 1225 tests passed. |
| Release build | PASS | `swift build -c release` → build complete. |
| Python E2E syntax | PASS | `PYTHONPYCACHEPREFIX=/private/tmp/lpm-pycache python3 -m py_compile Scripts/live-e2e-test.py` exit 0. |

## Release-Binary Read-Only Smoke (Logic Pro 12.2 host)

```json
{
 "ok": true,
 "resource_count": 11,
 "template_count": 5,
 "stock_catalog_valid": true,
 "stock_entry_count": 103,
 "stock_census_states": {"inferred": 6, "manifested": 97},
 "logic_version": "12.2",
 "stock_gain_state": "manifested",
 "gain_presets": ["#default", "Convert To Mono", "Invert Phase - Left", "Invert Phase - Right"],
 "gain_source_path": "/Applications/Logic Pro.app/Contents/Resources/Plug-In Settings/Gain",
 "search_reverb_count": 4,
 "malformed_uri_fails_closed": true
}
```

`resource_count` is 11 because `logic://mcu/state` is hidden while the MCU surface is disconnected.

97/103 entries are `manifested` from real per-plugin folder probes on this machine; the 6 remaining stay honestly `inferred` (their factory content lives outside the probed roots). `verified`, `observed`, `unavailable`, and `readback_mismatch` are absent from production output by design — they require injected live-census evidence.

## Convergence Round 2→3

A cross-branch round-2 re-review (Codex gpt-5.5 xhigh on the sibling #15 branch) surfaced one routing edge shared by both branches: doubled/trailing-slash paths (`logic://stock-plugins//census`, `.../census/`) were silently normalized by segment splitting. Fixed with a canonical-path guard in `readStockPluginResource` plus fail-closed regression tests. `swift test --no-parallel` → 1225 tests passed after the fix.

## Claim Boundary (unchanged)

Read-only discovery only. No write-side broadening. `verified` labels remain provenance-gated; parameter verification still requires explicit readback evidence. Live insert/readback evidence for the guarded Gain path remains `docs/tickets/mixer-verification/VERIFICATION-2026-06-09.md`.
