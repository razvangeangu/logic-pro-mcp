# Live Verification — v3.6.0

Date: 2026-06-19 KST
Scope: release-tree evidence for PR #24 (`logic_plugins` verified plugin apply-back) plus PR #54 / issue #59 Logic 12.2 AX readback hardening. Published artifact hashes and workflow IDs are filled after the `v3.6.0` release workflow completes.

## Claim Boundary

This document verifies the v3.6.0 release-tree behavior on the local macOS/Logic Pro 12.2 environment and the PR #24 review evidence. It is not a notarization/signing claim and not coverage for every Logic Pro version, locale, project shape, parent-app TCC context, clean host, or future macOS update.

Published release metadata and SHA256 values are recorded in `docs/releases/v3.6.0.md` after the GitHub Actions release workflow publishes artifacts. Previous stable evidence remains in `docs/live-verify-v3.5.0.md`.

## Deterministic Gates

| Gate | Result | Evidence |
|---|---:|---|
| PR #24 focused plugin suites | PASS | Focused Swift suite `63/63`; `AXPluginInsertSlotsDriftTests` `6/6`; `PluginInsertVerifiedTests` `31/31`; `PluginGetInventoryTests` `8/8`; `VerifiedOpGateTests` `3/3`. |
| PR #24 full suite | PASS | `swift test --no-parallel` -> `1384/1384` passed on the exact-slot plugin branch. |
| PR #24 release build | PASS | `swift build -c release` passed. |
| PR #24 live E2E syntax | PASS | `python3 -m py_compile Scripts/live-e2e-test.py` passed. |
| PR #24 removed-path grep | PASS | Stale Search-and-Add helper/strategy names returned `0` matches after final exact-slot implementation. |
| PR #54 / issue #59 focused AX tests | PASS | Focused `AXLogicProElements` / `AXValueExtractors` tests `30/30` passed after the track-header/type-inference hardening. |
| PR #54 / issue #59 full suite | PASS | `swift test --no-parallel` -> `1388/1388` passed. |
| PR #54 / issue #59 release build | PASS | `swift build -c release` passed. |
| v3.6.0 whitespace | PASS | `git diff --check` passed after the PR #24 merge, conflict resolution, version bump, and release-doc update. |
| v3.6.0 Formula syntax | PASS | `ruby -c Formula/logic-pro-mcp.rb` -> `Syntax OK`. |
| v3.6.0 live E2E syntax | PASS | `python3 -m py_compile Scripts/live-e2e-test.py` passed. |
| v3.6.0 full suite | PASS | `swift test --no-parallel` -> `1396/1396` passed on the release tree. |
| v3.6.0 release build | PASS | `swift build -c release` passed on the release tree. |

## Live Logic Pro 12.2 Evidence

| Gate | Result | Evidence |
|---|---:|---|
| Exact-slot plugin insert | PASS | `logic_plugins.insert_verified track=6 insert=6 plugin=Gain` returned State A with `verified:true`, `observed_slot:6`, `write_source:"ax_exact_slot_popup"`, `slot_popup_anchor_verified:true`, and `winning_strategy:"slot_popup_direct_exact_leaf"`. Independent `get_inventory` readback confirmed the requested slot contained Gain. |
| Cleanup readback | PASS | Follow-up inventory confirmed track 6 inserts 5/6/7 were empty after cleanup. |
| Strict live E2E on PR #24 tree | PASS | `LOGIC_PRO_MCP_STRICT_LIVE=1 Scripts/live-e2e-test.sh` / Python harness evidence: `314` passed, `0` skipped, `0` failed on the exact-slot plugin tree. |
| Strict live E2E on v3.6.0 release tree | PASS | `LOGIC_PRO_MCP_STRICT_LIVE=1 Scripts/live-e2e-test.sh` -> `314` passed, `0` skipped, `0` failed with server `v3.6.0`, 7 channels ready, and Logic Pro 12.2 connected. |
| Tracks resource readback | PASS | Live read-only probe after the Logic 12.2 header fix returned `logic://tracks` with `source:"ax_live"`, real visible names, `placeholder_count:0`, and `unknown_type_count:0`. |
| Transport cycle readback | PASS | Manual cycle toggle/resource roundtrip reflected `isCycleEnabled false -> true`, confirming the resource read path follows the verified control-bar readback path. |

## HC v2 Surface Verified

`logic_plugins.*` uses HC v2 and remains single-channel by design:

- `get_inventory` is read-only and returns slot `read_status`, `complete`, and canonical plugin IDs where known.
- `insert_verified` has no fallback path beyond the verified Accessibility exact-slot popup route.
- `set_param_verified` returns State A only after AX slider write/readback tolerance check; unsupported plugin parameters fail before writing.
- State C includes `verified:false` and terminal error codes so callers cannot confuse a hard failure with legacy send-only success.

## Remaining Non-Claimed Surface

- Published `v3.6.0` artifact SHA256 values, Formula SHA sync, and GitHub Release workflow IDs are filled after the workflow publishes artifacts.
- `set_param_verified` currently verifies only Compressor `threshold`; arbitrary plugin parameter readback remains future work.
- `set_param_verified` still requires the target plugin window to already be open.
- Multi-version Logic matrix remains future verification work.
