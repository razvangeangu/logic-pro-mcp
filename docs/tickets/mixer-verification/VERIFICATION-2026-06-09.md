# Verification Evidence — mixer-verification-honesty / Issues #10-13

Date: 2026-06-09 KST
Repo: `/Users/isaac/projects/logic-pro-mcp`
Scope: current working tree, stable `v3.4.5` release tag, Logic Pro 12.2 live session, release binary `.build/release/LogicProMCP`, published GitHub Release artifacts.

## Claim Boundary

This is a hard verification pass for the current #10-#13 work in the current machine/environment. It is not a universal guarantee across every Logic Pro version, locale, project shape, parent-app TCC context, clean host, notarized release artifact, or future OS update.

## Deterministic Gates

| Gate | Result | Evidence |
|---|---:|---|
| Targeted flake repro | PASS | `swift test --no-parallel --filter testProductionMCUTransportReceiveParsesFeedbackEvents` passed after replacing the two-yield wait with a bounded event wait. |
| Full test suite | PASS | `swift test --no-parallel` -> `1197 tests passed`, 0 fail. |
| Release build | PASS | `swift build -c release` -> build complete. |
| Python E2E syntax | PASS | `python3 -m py_compile Scripts/live-e2e-test.py` exit 0. |
| Coverage test run | PASS | `swift test --enable-code-coverage --no-parallel` -> `1197 tests passed`, 0 fail. |
| Coverage threshold | PASS | `TOTAL 5587 1654 70.40% 1642 446 72.84% 15537 3452 77.78%`. Current CI hard gate is region >=70%, line >=77%; line >=90% remains the tracked target. |
| Strict live E2E | PASS | `LOGIC_PRO_MCP_STRICT_LIVE=1 Scripts/live-e2e-test.sh` -> `285 passed`, `0 skipped`, `285 total`. |
| GitHub Release workflow | PASS | `27183025739` completed successfully: `build`, `validate-install (macos-15)`, and `validate-install (macos-14)` all passed. |
| Published metadata | PASS | `RELEASE-METADATA.json` reports `version:"v3.4.5"`, `team_id:"ADHOC"`, `signing:"adhoc"`, `architectures:["x86_64","arm64"]`; `SHA256SUMS.txt` includes all three binary artifacts. |

## Flake Closed During This Pass

The first full deterministic run exposed one real suite reliability failure:

```text
testProductionMCUTransportReceiveParsesFeedbackEvents
Expectation failed: events == ["noteOn:0:64:127"], actual events == []
```

Root cause: the test emitted a CoreMIDI callback, then waited with `Task.yield()` twice for a separately scheduled receive task. Under full-suite load that was not a deterministic synchronization point. The test now waits up to 50 ms for the recorder to observe the expected event, keeping the production behavior unchanged while removing the false negative.

Changed file:

```text
Tests/LogicProMCPTests/LogicProServerTransportTests.swift
```

A later full strict live E2E run exposed one harness timing issue, not a production failure: the script clicked `toggle_cycle` and expected `logic://transport/state` to change after a fixed `0.3s`, even though the resource is populated by the 3-second AX poller cache. Reproduction showed the toggle applied and the resource changed on the next poll. The harness now uses a bounded wait for the resource value to change.

Changed file:

```text
Scripts/live-e2e-test.py
```

## Live Logic 12.2 Targeted Gate

Environment observed by `logic_system health`:

| Field | Value |
|---|---|
| Logic Pro | running |
| Logic Pro version | 12.2 |
| Project | `무제 20 - 트랙` |
| Track count | 8 initially; 11 visible mixer strips during live verification after AX refresh |
| Accessibility | granted |
| Automation | granted |
| CoreMIDI | ready |
| MCU | ready, registered, feedback active |
| MIDIKeyCommands | ready |
| Scripter | ready |

Targeted issue checks:

| Issue | Result | Evidence |
|---|---:|---|
| #10 | PASS | `logic_mixer set_volume {track:0,value:0.36}` returned `success:true`, `verified:true`, `verify_source:"ax_readback"`, `observed_ax:0.33777777777777773`, `observed_mcu:null`. |
| #11 | PASS | Post-write `logic://mixer` returned `data_source:"ax_poll"` and strip 0 `volume:0.33777777777777773`, matching the AX readback. |
| #12 | PASS | `logic://mixer` strip 0 returned `plugins_source:"ax"` and the plugin snapshot `["Gain","Gain","Gain","Gain","Gain","Drum Machine Designer"]`. |
| #13 confirmation | PASS | `insert_plugin` without `confirmed:true` returned `confirmation_required:true` with an explicit L2 confirm command. |
| #13 insert | PASS | `insert_plugin {track:0,slot:6,plugin_name:"Gain",confirmed:true}` returned `success:true`, `verified:true`, `verify_source:"ax_plugin_slot"`, `observed_plugin_name:"Gain"`. |
| #13 occupied guard | PASS | Repeating the same insert into slot 6 failed closed with `channels_exhausted` / `slot_occupied`, refusing replacement. |

## Remaining Non-Claimed Surface

- Full strict live E2E was run after the harness timing fix: `285 passed`, `0 skipped`, `0 failed`. The run includes broad editor/project actions (`cut`, `delete`, `paste`, `bounce`, renames, marker creation, etc.) against the current local Logic session.
- C1 version finalize is part of the v3.4.5 release pass. Published SHA256 lockstep and GitHub Actions macOS 14/15 install validation are verified for the stable release artifacts.
- Multi-version Logic matrix is release-follow-up work, not closed by this pass.
- The current verified claim is: #10-#13 are fixed and verified for the current working tree against Logic Pro 12.2 on this machine, with deterministic tests, release build, coverage gate, full strict live E2E, and targeted live E2E all green.
