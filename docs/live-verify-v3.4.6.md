# Live Verification — v3.4.6

Date: 2026-06-09 KST
Scope: stable `v3.4.6` release tag, current mainline source, local deterministic gates, published GitHub Release artifacts, and carried Logic Pro 12.2 live evidence from the final current-main mixer attestation.

## Claim Boundary

This verifies v3.4.6 on the current macOS host, local deterministic test environment, and GitHub Actions release surface. The Logic Pro 12.2 live behavior claim is carried from the final current-main attestation because v3.4.6 is a version, packaging, and documentation alignment release only. It does not claim coverage for every Logic Pro version, locale, project shape, parent-app TCC context, clean host, or future macOS update.

Published release metadata, SHA256 values, and workflow evidence are recorded in `docs/releases/v3.4.6.md`.

## Deterministic Gates

| Gate | Result | Evidence |
|---|---:|---|
| Python live E2E syntax | PASS | `python3 -m py_compile Scripts/live-e2e-test.py` exit 0. |
| Formula syntax | PASS | `ruby -c Formula/logic-pro-mcp.rb` -> `Syntax OK`. |
| Version lockstep | PASS | `swift test --filter VersionConsistencyTests --no-parallel` -> 1 test passed. |
| Coverage test run | PASS | `swift test --enable-code-coverage --no-parallel` -> 1197 tests passed, 0 failed. |
| Coverage threshold | PASS | TOTAL region 70.81%, line 78.32%. Current CI hard gate is region >=70%, line >=78%; line >=90% remains the tracked target. |
| Release build | PASS | `swift build -c release` -> build complete. |
| Stable release preflight | PASS | `Scripts/release-stable.sh v3.4.6` -> py_compile, `swift test --no-parallel` 1197 passed, release build passed, tag pushed. |
| GitHub Release workflow | PASS | Run `27186085967`: `build`, `validate-install (macos-15)`, and `validate-install (macos-14)` all passed. |

## Live Logic Pro 12.2 Evidence

v3.4.6 does not change the Logic runtime implementation from the final v3.4.5 current-main verification. The current live evidence remains:

| Gate | Result | Evidence |
|---|---:|---|
| Strict live E2E | PASS | `LOGIC_PRO_MCP_STRICT_LIVE=1 Scripts/live-e2e-test.sh` -> 285 passed, 0 skipped, 0 failed. |
| #10 | PASS | `set_volume` verified via AX readback with `verify_source:"ax_readback"` after Logic 12.2 omitted MCU echo. |
| #11 | PASS | `logic://mixer` refreshed from AX poll with `data_source:"ax_poll"`. |
| #12 | PASS | `logic://mixer` exposed AX-sourced plugin snapshots with `plugins_source:"ax"`. |
| #13 | PASS | Guarded `insert_plugin` required Level-2 confirmation, verified the inserted Gain slot, and refused occupied-slot replacement. |

Detailed live payload values are preserved in `docs/tickets/mixer-verification/VERIFICATION-2026-06-09.md`.

## Release Artifact Gate

| Artifact | SHA256 |
|---|---|
| `LogicProMCP` | `d8d17df6c6f71485c48e53aff91308d36e10d1ba0cdc479c098e0af71b6ad5f3` |
| `LogicProMCP-macOS-universal.tar.gz` | `6420274b4fbbb863226a2a163b971a36161c10880e8f3a06d979100a35bc01d3` |
| `LogicProMCP-macOS-arm64.tar.gz` | `6420274b4fbbb863226a2a163b971a36161c10880e8f3a06d979100a35bc01d3` |

Published metadata:

```json
{"version":"v3.4.6","team_id":"ADHOC","signing":"adhoc","architectures":["x86_64","arm64"]}
```

## Remaining Non-Claimed Surface

- Multi-version Logic matrix remains future verification work.
- Full per-parameter plugin value readback and arbitrary `set_plugin_param insert:N` routing remain future work; v3.4.6 ships plugin-slot snapshots, send-only Scripter write honesty, and guarded plugin insertion.
