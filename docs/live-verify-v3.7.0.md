# Live Verification — v3.7.0

Date: 2026-06-23 KST
Scope: release-tree evidence for the accumulated v3.6.0 -> v3.7.0 feature and bug-fix set, including the 10-tool / 18-resource / 11-template source tree, issue #60 EN/KO live close gate, and v43 demo QA closure work.

## Claim Boundary

This document verifies the v3.7.0 release tree on the local macOS / Logic Pro 12.2 environment, GitHub CI surfaces available at release prep, and the published GitHub Release workflow. It is not a notarization claim and not coverage for every Logic Pro version, locale, project shape, MCP parent-app TCC context, clean host, or future macOS update.

Published artifact hashes and workflow IDs are recorded in `docs/releases/v3.7.0.md`. Previous stable evidence remains in `docs/live-verify-v3.6.0.md`.

## Deterministic Gates

| Gate | Result | Evidence |
|---|---:|---|
| Worktree base | PASS | Release branch created from `origin/main` at `79d06aa0d01f3f55839f8062d02fe20d2f99089a`. |
| Open issue check | PASS | `gh issue list --state open --limit 300` returned `[]`. |
| Open PR check | PASS | `gh pr list --state open --limit 100` returned `[]`. |
| Version surfaces | PASS | `ServerConfig`, `manifest.json`, `server.json`, Formula version, installer default, startup-banner tests, and version-consistency tests point at `3.7.0`. |
| Python bootstrap unit test | PASS | `python3 Scripts/logic_session_bootstrap_test.py` -> `14` passed. |
| Python modal unit test | PASS | `python3 Scripts/logic_free_tempo_modal_test.py` passed. |
| Python syntax | PASS | `python3 -m py_compile Scripts/live-e2e-test.py Scripts/logic_session_bootstrap.py Scripts/logic_session_bootstrap_test.py Scripts/logic_free_tempo_modal.py Scripts/logic_free_tempo_modal_test.py` passed. |
| Formula syntax | PASS | `ruby -c Formula/logic-pro-mcp.rb` -> `Syntax OK`. |
| Release build | PASS | `swift build -c release` passed on the v3.7.0 release tree. |
| Full Swift suite | PASS | `swift test --no-parallel` -> `1743` passed, `0` failed. |
| PR #166 CI | PASS | GitHub Actions CI build/test/coverage for PR #166 succeeded. |
| Stable release workflow | PASS | Release run `27997558936` passed build plus macOS 14/15 install validation. |

## Focused Close Gates

| Gate | Result | Evidence |
|---|---:|---|
| Issue #60 locale phase tests | PASS | `swift test --filter Issue60LocalePhase --no-parallel` -> `19` passed. |
| AXLocalePolicy tests | PASS | `swift test --filter AXLocalePolicy --no-parallel` -> `25` passed. |
| AXLogicProElements tests | PASS | `swift test --filter AXLogicProElements --no-parallel` -> `24` passed. |
| MCU echo determinism | PASS | PR #153 CI and focused test evidence removed the parallel-load flake. |
| Demo/render gate tests | PASS | v43 demo QA closure PRs #152 and #155-#158 cover fail-closed render, capture finalize, press-any timeout, play timeout, and don't-save modal behavior. |

## Live Logic Pro 12.2 Evidence

| Gate | Result | Evidence |
|---|---:|---|
| Strict fresh EN close gate | PASS | `LOGIC_PRO_MCP_STRICT_LIVE=1 LOGIC_PRO_MCP_BOOTSTRAP_FRESH=1 LOGIC_PRO_MCP_BOOTSTRAP_LANGUAGE=en python3 Scripts/live-e2e-test.py` -> `341` passed, `0` skipped. |
| Strict fresh KO close gate | PASS | `LOGIC_PRO_MCP_STRICT_LIVE=1 LOGIC_PRO_MCP_BOOTSTRAP_FRESH=1 LOGIC_PRO_MCP_BOOTSTRAP_LANGUAGE=ko python3 Scripts/live-e2e-test.py` -> `341` passed, `0` skipped. |
| System Events-free bootstrap | PASS | PR #166 replaced the live readiness probe with native AX / NSWorkspace and CGEvent helpers; strict live close gates passed without the System Events AppleEvent path. |
| Verified plugin apply-back carryover | PASS | v3.6.0 exact-slot `logic_plugins.insert_verified` and Compressor threshold readback evidence remains the current verified apply-back boundary; see `docs/live-verify-v3.6.0.md`. |

## Current Non-Claims

- Multi-version Logic matrix is still future verification work.
- Notarized Developer ID release is not claimed when the workflow runs in ADHOC mode.
- `logic_plugins.set_param_verified` still verifies only Compressor `threshold`.
- Live behavior outside the EN/KO strict close gate and the documented Logic Pro 12.2 evidence remains unclaimed unless a PR-specific live proof names it.

## Release Publication Gate

After `v3.7.0` tag publication:

- GitHub Release workflow build job passed.
- `validate-install (macos-14)` passed.
- `validate-install (macos-15)` passed.
- Published assets include `LogicProMCP`, `LogicProMCP-macOS-universal.tar.gz`, `LogicProMCP-macOS-arm64.tar.gz`, `SHA256SUMS.txt`, and `RELEASE-METADATA.json`.
- `RELEASE-METADATA.json` reports `version:"v3.7.0"` and `architectures:["x86_64","arm64"]`.
- Formula SHA is synced from the published universal tarball SHA: `61a13ef9c59e95c2ac39803acc48019259abeba7e45a0e475ce24b9678b6be79`.
