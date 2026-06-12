# Live Verification — v3.5.0

Date: 2026-06-12 KST
Scope: stable `v3.5.0` release tag, current mainline source, local deterministic gates, published GitHub Release artifacts, and fresh Logic Pro 12.2 strict live E2E evidence captured on the release tree.

## Claim Boundary

This verifies v3.5.0 on the current macOS host, local deterministic test environment, and GitHub Actions release surface. The Logic Pro 12.2 live behavior claim is a fresh strict live E2E run executed on the exact release tree (source commit `36fc80f`) against a live Logic Pro 12.2 session on this host. It does not claim coverage for every Logic Pro version, locale, project shape, parent-app TCC context, clean host, or future macOS update.

Published release metadata, SHA256 values, and workflow evidence are recorded in `docs/releases/v3.5.0.md`.

## Deterministic Gates

| Gate | Result | Evidence |
|---|---:|---|
| Python live E2E syntax | PASS | `python3 -m py_compile Scripts/live-e2e-test.py` exit 0. |
| Formula syntax | PASS | `ruby -c Formula/logic-pro-mcp.rb` -> `Syntax OK`. |
| Manifest surface | PASS | `manifest.json` parses; 14 resources + 7 templates, cross-checked against the live `ResourceProvider` surface by `VersionConsistencyTests`. |
| Full deterministic suite | PASS | `swift test` (parallel) -> 1276 passed; `swift test --no-parallel` -> 1276 passed (release-stable.sh preflight). |
| Coverage test run | PASS | `swift test --enable-code-coverage --no-parallel` -> 1276 passed on the release tree. |
| Coverage threshold | PASS | Local TOTAL region 75.51%, line 83.04% (CI hard gate is region >=70%, line >=78%; line >=90% remains the tracked target). CI coverage gate also passed on the release commit (run `27420550145`). |
| Release build | PASS | `swift build -c release` -> build complete. |
| Stable release preflight | PASS | `Scripts/release-stable.sh v3.5.0` -> py_compile, `swift test --no-parallel` 1276 passed, release build passed, tag pushed. |
| GitHub Release workflow | PASS | Run `27421259014`: `build`, `validate-install (macos-15)`, and `validate-install (macos-14)` all passed. |

## Live Logic Pro 12.2 Evidence

Fresh strict live E2E on the v3.5.0 release tree (Logic Pro 12.2 open with a real project, tmux-parent transport so macOS TCC evaluates the live client context, skips converted to failures):

| Gate | Result | Evidence |
|---|---:|---|
| Strict live E2E | PASS | `LOGIC_PRO_MCP_STRICT_LIVE=1 python3 Scripts/live-e2e-test.py` -> 313 passed, 0 skipped, 0 failed (2026-06-12). |
| Surface parity | PASS | The same 313/0/0 result was independently reproduced on the merged PR #21 tree earlier the same day, before the version bump — the only diff between the trees is version strings and documentation. |

The run exercises the full public surface, including the new stock-plugin and workflow-skill resources/templates, fail-closed malformed-URI routing, dispatcher validation rejections, transport/track/mixer mutations, performance bounds, and memory stability (57.3 MB stable across the run).

## Release Artifact Gate

| Artifact | SHA256 |
|---|---|
| `LogicProMCP` | `5d8c60eb7a4b0977255f467e4035e5894352bed3d624082a46e0485f06a6b1e0` |
| `LogicProMCP-macOS-universal.tar.gz` | `d8c3e9555db985271da156f63967fb78866b5204442eea8dd0233b46b3356489` |
| `LogicProMCP-macOS-arm64.tar.gz` | `d8c3e9555db985271da156f63967fb78866b5204442eea8dd0233b46b3356489` |

Published metadata:

```json
{"version":"v3.5.0","team_id":"ADHOC","signing":"adhoc","architectures":["x86_64","arm64"]}
```

## Remaining Non-Claimed Surface

- Multi-version Logic matrix remains future verification work; current live evidence is Logic Pro 12.2 on this host plus GitHub Actions macOS 14/15 installer validation.
- `record_sequence` still reports through its documented pre-Honest-Contract response shape (custom JSON success dict, descriptive text errors); extending the HC envelope to the remaining mutating ops is tracked backlog from v3.1.x.
- Full per-parameter plugin value readback and arbitrary `set_plugin_param insert:N` routing remain future work; v3.5.0 ships provenance-gated catalog truth states, plugin-slot snapshots, and the guarded insert path.
- Workflow `live_verified` claims are gated on in-repo evidence-file existence; semantic re-verification of each recipe per release remains follow-up.
