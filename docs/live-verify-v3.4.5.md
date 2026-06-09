# Live Verification — v3.4.5

Date: 2026-06-09 KST
Scope: stable `v3.4.5` release tag, local release binary `.build/release/LogicProMCP`, Logic Pro 12.2 live session, published GitHub Release artifacts.

## Claim Boundary

This verifies v3.4.5 on the current macOS host and live Logic Pro 12.2 environment. It does not claim coverage for every Logic Pro version, locale, project shape, parent-app TCC context, clean host, or future macOS update. Published release metadata, SHA256 values, and workflow evidence are recorded in `docs/releases/v3.4.5.md`.

## Deterministic Gates

| Gate | Result | Evidence |
|---|---:|---|
| Full test suite | PASS | `swift test --no-parallel` -> 1197 tests passed, 0 failed. |
| Release build | PASS | `swift build -c release` -> build complete. |
| Python live E2E syntax | PASS | `python3 -m py_compile Scripts/live-e2e-test.py` exit 0. |
| Coverage test run | PASS | `swift test --enable-code-coverage --no-parallel` -> 1197 tests passed, 0 failed. |
| Coverage threshold | PASS | TOTAL region 70.40%, line 77.78%. Current CI hard gate is region >=70%, line >=77%; line >=90% remains the tracked target. |
| Strict live E2E | PASS | `LOGIC_PRO_MCP_STRICT_LIVE=1 Scripts/live-e2e-test.sh` -> 285 passed, 0 skipped, 285 total. |
| GitHub Release workflow | PASS | Run `27183025739`: `build`, `validate-install (macos-15)`, and `validate-install (macos-14)` all passed. |

## Flake Closed During Final Verification

The first final full-suite run exposed one suite reliability failure:

```text
testProductionMCUTransportReceiveParsesFeedbackEvents
Expectation failed: events == ["noteOn:0:64:127"], actual events == []
```

The test emitted a CoreMIDI callback, then waited with two `Task.yield()` calls for a separately scheduled receive task. Under full-suite load, that was not deterministic synchronization. The test now uses a bounded wait for the recorder to observe the expected event. Production MIDI behavior was unchanged.

The first full strict live E2E pass also exposed a harness timing issue in the cycle roundtrip check. `logic_transport toggle_cycle` clicked the Cycle control successfully, but the script expected the cached `logic://transport/state` resource to change after a fixed `0.3s`. The resource is refreshed by the AX poller, so the test now uses a bounded wait for the next cache update. Production transport behavior was unchanged.

## Live Logic Pro 12.2 Targeted Gate

Observed environment:

| Field | Value |
|---|---|
| Logic Pro | running |
| Logic Pro version | 12.2 |
| Project | `무제 20 - 트랙` |
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
| #13 confirmation | PASS | `insert_plugin` without `confirmed:true` returned `confirmation_required:true` and an explicit Level-2 confirm command. |
| #13 insert | PASS | `insert_plugin {track:0,slot:6,plugin_name:"Gain",confirmed:true}` returned `success:true`, `verified:true`, `verify_source:"ax_plugin_slot"`, `observed_plugin_name:"Gain"`. |
| #13 occupied guard | PASS | Repeating the same insert into slot 6 failed closed with `channels_exhausted` / `slot_occupied`, refusing replacement. |

## Remaining Non-Claimed Surface

- Full strict live E2E was run after the harness timing fix: 285 passed, 0 skipped, 0 failed. The run includes broad editor/project actions (`cut`, `delete`, `paste`, `bounce`, renames, marker creation) against the current local Logic session.
- Clean-host-like install validation is covered by the GitHub Actions release workflow on macOS 14 and macOS 15 and recorded in `docs/releases/v3.4.5.md`; it is not a substitute for every possible user machine, parent app, or TCC profile.
- Multi-version Logic matrix remains future verification work.
- Full per-parameter plugin value readback and arbitrary `set_plugin_param insert:N` routing remain future work; v3.4.5 ships plugin-slot snapshots, send-only Scripter write honesty, and guarded plugin insertion.
