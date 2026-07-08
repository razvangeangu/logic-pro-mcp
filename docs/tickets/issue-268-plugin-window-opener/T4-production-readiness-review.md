# T4 - Production Readiness Review and PR

## Goal

Ship the fix as a reviewable PR with evidence.

## Acceptance

- [x] Diff contains only PRD, tickets, implementation, tests, and evidence.
- [x] Relevant tests and build pass.
- [x] Live E2E evidence is summarized in the PR.
- [x] PR links and closes #268.
- [x] #268 receives a short status comment pointing to the PR.

## Verification

- `git diff --stat`
- `gh pr view`
- PR: https://github.com/MongLong0214/logic-pro-mcp/pull/271
- Issue comment:
  https://github.com/MongLong0214/logic-pro-mcp/issues/268#issuecomment-4910876825
- `swift test --filter PluginSetParamVerifiedLiveTests` passed 19/19.
- `swift test --no-parallel` passed 2214/2214.
- `swift build -c release` passed.
- LSP diagnostics for changed Swift files are clean.

## Review Notes

- The implementation does not relax State A. It only replaces the missing
  production opener between the existing occupied-slot gate and the existing
  slider write/readback gate.
- Opened windows are not trusted by title alone; the requested AX slider must be
  found before a write can happen.
- If acquisition fails, the payload stays State C with `write_attempted:false`
  and includes bounded candidate window/slider evidence for the next report.

## Runtime Audit

- Hypothesis 1: the original failure is caused by the production opener being a
  no-op. Evidence: red-first fixture failed with State C `window_open_failed`
  before the opener was wired, then passed after the target-slot opener.
- Hypothesis 2: opening the wrong window could cause an unsafe write. Evidence:
  `testProductionOpenerRejectsOpenedWindowWithoutRequestedSlider` opens a window
  without the requested `Threshold` slider and still returns State C with
  `write_attempted:false`.
- Hypothesis 3: the fix might only work in fixtures and not through the real MCP
  surface. Evidence: branch release binary E2E on live Logic Pro 12.3 returned
  State A verified for `logic_plugins.set_param_verified` on Compressor
  `threshold`; bad input through the same MCP surface returned State C
  `invalid_params` before any write.
