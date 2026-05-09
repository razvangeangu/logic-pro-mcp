# Enterprise Production Readiness Full-Scope Review

Date: 2026-05-09  
Scope: full repository, including `Sources/`, `Tests/`, `Scripts/`, `.github/`, `Formula/`, root docs, and existing release/review docs  
Review mode: final enterprise go-live gate, review-only, no production code changes  
Decision: `HARD NO-GO` / `RELEASE BLOCKED` / `NOT PRODUCTION READY`

## Executive Verdict

This repository is not ready for commercial production release. The build and most deterministic unit/in-process test suites pass, but the current artifact cannot be certified because several write paths can still mutate the wrong target, the intended stdio launch path fails live integration checks, signal shutdown bypasses cleanup, release provenance is not enterprise fail-closed, and the E2E evidence set itself contains false-positive expectations.

The most important correction to prior review language is this: some live failures are environment/precondition failures, not direct proof that Logic Pro is absent. However, that does not reduce the severity. The product is a stdio MCP server, so when the stdio-launched release binary reports `logic_pro_running:false`, cannot initialize CoreMIDI, and cannot see permissions on the same host where System Events can see a Logic Pro window, that is a production launch-topology defect until proven otherwise.

Current release blockers:

| ID | Area | Severity | Release impact |
|---|---|---:|---|
| RB-1 | Mutating dispatcher fail-open / wrong-target writes | P0 | Blocks any commercial DAW automation release |
| RB-2 | Stdio live launch path reports false runtime state and loses CoreMIDI | P0 | Blocks intended MCP deployment topology |
| RB-3 | `SIGTERM` / `SIGINT` bypass coordinated cleanup | P0 | Blocks supervised production operation |
| RB-4 | Release provenance allows ADHOC production artifacts | P0 | Blocks enterprise distribution |
| RB-5 | E2E harness integrity is insufficient and partially false-positive | P1 | Blocks credible release attestation |
| RB-6 | Install/uninstall rollback is not non-interactive-safe enough | P1 | Blocks managed fleet rollout |

## Evidence Standard

Only the following evidence was treated as production-relevant:

| Accepted | Rejected as proof |
|---|---|
| Fresh command output from this workspace on 2026-05-09 | Historical docs claiming prior success |
| Current `release` binary checks where possible | Debug-only success as release proof |
| Code line evidence from current files | Comments that describe intended behavior but contradict code |
| Live stdio runs and process-level probes | "Response exists" checks that do not prove side effects |
| Install/uninstall rehearsal with explicit temp paths | Claims of clean-host readiness without clean-host evidence |

This review also used the existing project docs aggressively. When docs contradicted runtime or current code, the contradiction was logged as a finding rather than averaged away.

## Corrections To Avoid Prior Invalid Findings

Several earlier judgments needed tightening:

| Prior pattern | Corrected interpretation |
|---|---|
| Treating `Logic Pro not running` from health as absolute truth | It is a launch-context mismatch. System Events returned an actual Logic Pro window, so the product must explain and handle the mismatch. |
| Treating `spctl --assess` local failure as release artifact failure | Local `.build/release` assessment returned `internal error in Code Signing subsystem`; this is not a notarized release artifact test. It remains a missing release evidence item, not standalone proof that GitHub release artifacts fail Gatekeeper. |
| Treating temp install/uninstall rehearsal as clean-host proof | It is only scoped rollback evidence. It does not replace clean macOS install, Homebrew tap install, notarized install, or MDM-style uninstall rehearsal. |
| Treating all `as! AXValue` occurrences as crash bugs | Most force casts are preceded by `CFGetTypeID(...AXValueGetTypeID())`. Only unguarded helpers remain a crash-hardening issue. |
| Treating in-process `EndToEndTests` as live E2E proof | They are valuable contract tests, but most complete in milliseconds using mocks or deterministic seams. They do not prove Logic Pro side effects. |
| Treating live harness pass count as trustworthy | The harness includes weak expectations such as "responds" for mutating calls and even expects missing mixer params to default. It needs repair before it can certify release readiness. |

## Verification Matrix

Fresh verification run in this review:

| Check | Command / method | Result | Production interpretation |
|---|---|---:|---|
| Dependencies | `swift package show-dependencies` | Pass | SwiftPM graph resolves. |
| Release build | `swift build -c release` | Pass | Binary builds, but build success does not cover live OS integration. |
| Full tests | `swift test --no-parallel` | `1083` pass | Deterministic suite is broad and valuable. It does not close live blockers. |
| Coverage test run | `swift test --enable-code-coverage --no-parallel` | `1083` pass | Coverage run passes but emits many Swift Testing deprecation warnings. |
| Coverage report | `xcrun llvm-cov report ...` | Total lines `77.55%`, regions `70.56%` | OS/UI integration surfaces remain under-covered. |
| In-process E2E suite | `swift test --no-parallel --filter EndToEndTests` | `96` pass | Contract/in-process E2E passes; not a live Logic proof. |
| Commercial/production suite | `swift test --no-parallel --filter 'CommercialReadinessTests|ProductionReadinessTests'` | `53` pass | Useful safety tests pass; audit false-positive logs were visible during invalid project path tests. |
| Shell syntax | `bash -n Scripts/*.sh` for installer/live/release scripts | Pass | Syntax is valid. Behavior issues remain. |
| Shellcheck | `command -v shellcheck` | Missing | No shell lint evidence available locally. |
| Permissions check | `./.build/debug/LogicProMCP --check-permissions` | Exit `1` | Accessibility not granted, automation not verifiable according to the process. |
| Approval store | `./.build/debug/LogicProMCP --list-approvals` | KeyCmd and Scripter approved | Manual approval store exists, but live readiness still fails under stdio. |
| System Events probe | `osascript ... process "Logic Pro"` | Returned window title | Host can see Logic Pro via System Events, contradicting stdio health false-negative. |
| Debug live stdio | `python3 Scripts/live-e2e-test.py` | `198/244` pass, `46` fail | Live integration fails in intended subprocess topology. |
| Release live stdio | same harness with `BINARY='.build/release/LogicProMCP'` | `198/244` pass, `46` fail | Failure is not debug-binary-only. |
| Legacy shell live harness | `bash Scripts/live-e2e-test.sh` | `0/29` pass | Harness is unusable as release evidence. |
| Issue 7 live verify | `bash Scripts/issue7_live_verify.sh` | `FAIL: no open Logic document` | Requires manual precondition and is not self-sufficient attestation. |
| Codesign verify | `codesign --verify --strict --verbose=2 .build/release/LogicProMCP` | Pass | Local binary is code-signature-valid on disk. |
| Gatekeeper assess | `spctl --assess --type execute .build/release/LogicProMCP` | `internal error` | No valid notarized/Gatekeeper release proof from this local artifact. |
| Homebrew formula test | `brew test ./Formula/logic-pro-mcp.rb` | Rejected outside tap | Need tap-context install/test evidence. |
| Installer fail-closed | `bash Scripts/install.sh` without pins | Exit `1` | Good fail-closed behavior for missing provenance pins. |
| Temp uninstall, no auto-restore | `Scripts/uninstall.sh` with backup and no `AUTO_RESTORE` | Exit `1` after partial removal | Non-interactive uninstall is not fleet-safe. |
| Temp uninstall, auto-restore | same with `LOGIC_PRO_MCP_KEYCMD_AUTO_RESTORE=1` | Exit `0` | Auto-restore path works for covered file types. |
| Signal probe | real release process with FIFO stdin, then `SIGTERM` | Exit `0`, no cleanup logs | Signal path bypasses visible cleanup lifecycle. |

## Coverage Evidence

`llvm-cov` result after coverage test run:

| Metric | Current |
|---|---:|
| Region coverage | `70.56%` |
| Function coverage | `73.79%` |
| Line coverage | `77.55%` |

Lowest or most relevant surfaces:

| File | Line coverage | Region coverage | Risk |
|---|---:|---:|---|
| `Accessibility/AXMouseHelper.swift` | `0.00%` | `0.00%` | Mouse fallback is a high-risk UI integration path with no source coverage. |
| `Channels/AccessibilityChannel.swift` | `48.54%` | `40.80%` | Largest live AX surface remains under-covered. |
| `Accessibility/LibraryAccessor.swift` | `49.43%` | `44.87%` | Library navigation and instrument selection are commercial-critical. |
| `Accessibility/PluginInspector.swift` | `49.91%` | `45.77%` | Plugin inspection UI automation remains high-risk. |
| `Accessibility/AXLogicProElements.swift` | `72.91%` | `58.48%` | AX tree discovery still has uncovered branches. |
| `Utilities/ProcessUtils.swift` | `73.86%` | `66.98%` | Runtime detection mismatch is a release blocker, so this coverage is not enough. |

The coverage percentage is not the main problem. The problem is distribution: the uncovered and weakly covered files are the exact surfaces most likely to break under Logic version, locale, window focus, Accessibility, CoreMIDI, and launch-context variation.

## Live E2E Findings

The Python live harness is the stronger live evidence asset because it holds a persistent stdio client and receives JSON-RPC responses. It still failed `46/244` for both debug and release binaries.

Observed failure cluster:

| Cluster | Fresh evidence |
|---|---|
| Logic running detection | `health.logic_pro_running is true` failed; `project.is_running` returned `false`. |
| Permissions | Accessibility and automation health checks failed. |
| Transport | `transport.toggle_cycle` and `toggle_metronome` returned `Logic Pro is not running`. |
| CoreMIDI | All direct MIDI send paths failed with `CoreMIDI client not initialized`. |
| Stress | `20 rapid MIDI notes: 0/20 ok`. |
| Virtual ports | `LogicProMCP-MCU`, `KeyCmd`, `Scripter` ports not visible. |
| Final health | Permissions were still not granted at final check. |

Critical nuance: an escalated System Events probe returned a real Logic Pro window title on the same host. Therefore, the correct finding is not "Logic was definitely closed." The correct finding is "the release stdio launch topology cannot reliably observe or initialize the same Logic Pro environment that other macOS automation surfaces can see."

The legacy shell harness is worse. `Scripts/live-e2e-test.sh` uses a short-lived pipe per request and currently produced `0/29` with empty responses. It should not be used as release evidence until fixed or formally deprecated.

## Release Blockers

### RB-1: Mutating dispatchers still fail open to target `0`

Severity: P0  
Status: open  
Production impact: wrong track, wrong marker, or wrong channel strip can be mutated by malformed or omitted parameters.

Evidence:

| File | Lines | Problem |
|---|---:|---|
| `Sources/LogicProMCP/Dispatchers/DispatcherSupport.swift` | `3-14` | `intParam` defaults to `0`. |
| `Sources/LogicProMCP/Dispatchers/MixerDispatcher.swift` | `18-29` | `set_volume` accepts missing `track/index` and routes `index: "0"`. |
| `Sources/LogicProMCP/Dispatchers/MixerDispatcher.swift` | `31-42` | `set_pan` accepts missing `track/index` and routes `index: "0"`. |
| `Sources/LogicProMCP/Dispatchers/MixerDispatcher.swift` | `85-106` | `set_plugin_param` accepts missing `track`, `insert`, `param`, and `value` defaults. |
| `Sources/LogicProMCP/Dispatchers/NavigateDispatcher.swift` | `95-109` | `delete_marker` and `rename_marker` default missing `index` to `0`; `rename_marker` can route empty `name`. |
| `Sources/LogicProMCP/Dispatchers/TrackDispatcher.swift` | `83-101` | `delete` correctly refuses unverified selection. |
| `Sources/LogicProMCP/Dispatchers/TrackDispatcher.swift` | `104-116` | `duplicate` lacks the same verified-selection gate. |
| `Tests/LogicProMCPTests/DispatcherTests.swift` | `688-697` | Test comment explicitly preserves weaker `duplicate` gating for backward compatibility. |

Why this blocks release:

DAW automation must be fail-closed for write targets. A malformed MCP client, LLM retry, stale generated call, or missing parameter must not mutate track 0 or marker 0. This is not hypothetical because the helper default is centralized and the dispatchers use it on write paths.

Required gate:

| Gate | Required proof |
|---|---|
| All mutating commands use explicit required-param validation | Unit tests covering missing, non-numeric, negative, and ambiguous params for every mutating command. |
| `track.duplicate` uses verified-selection gate | State B select response test must refuse duplicate the same way delete refuses. |
| Mixer and marker missing target reject | Regression tests must assert no router operation was executed. |
| Live harness expectation fixed | `mixer.set_volume` without params must be expected to fail, not "respond." |

### RB-2: Intended stdio launch path fails live runtime detection and MIDI initialization

Severity: P0  
Status: open  
Production impact: the MCP client launch mode can report false state and lose functional channels.

Evidence:

| Evidence | Result |
|---|---|
| `Scripts/live-e2e-test.py:16-27` | Stdio subprocess starts `.build/debug/LogicProMCP` by default. |
| Release override of same harness | Same `198/244` result as debug. |
| `Sources/LogicProMCP/Utilities/ProcessUtils.swift:54-65` | AppKit access returns `nil` off-main when main runloop is not waiting. |
| `Sources/LogicProMCP/Utilities/ProcessUtils.swift:184-205` | fallback depends on `/bin/ps`, which can fail in restricted launch contexts. |
| `Sources/LogicProMCP/Utilities/ProcessUtils.swift:207-225` | System Events fallback runs via `/bin/zsh -lc osascript ...`, unlike the direct `osascript` pattern in `PermissionChecker`. |
| `Sources/LogicProMCP/Utilities/PermissionChecker.swift:113-118` | Automation is `not_verifiable` if `ProcessUtils` says Logic is not running. |
| Live stderr | CoreMIDI client creation failed and several channels started degraded. |

Why this blocks release:

The expected production deployment is stdio under an MCP client. If stdio launch sees a different system than interactive TTY launch, the product is not operable under its primary transport.

Required gate:

| Gate | Required proof |
|---|---|
| Stdio and TTY launch parity | Same channel startup, health, permissions, Logic running, and MIDI port visibility across both topologies. |
| Process detection hardened | Tests for AppKit nil, `ps` unavailable, System Events available, and direct osascript fallback. |
| Live MCP client rehearsal | Current release artifact launched by a real MCP client config with raw JSON logs. |
| Operator runbook clarity | If macOS privacy context differs by terminal/client, document exact grant path and expected bundle identity. |

### RB-3: Signal shutdown bypasses cleanup

Severity: P0  
Status: open  
Production impact: supervised restarts and incident shutdowns do not prove port/channel/poller cleanup.

Evidence:

| File | Lines | Problem |
|---|---:|---|
| `Sources/LogicProMCP/MainEntrypoint.swift` | `64-72` | `SIGTERM` and `SIGINT` handlers call `exit(0)` directly. |
| `Sources/LogicProMCP/Server/LogicProServer.swift` | `363-382` | Normal lifecycle has explicit `stopPoller`, `stopChannels`, and `stopPorts`. |
| Fresh signal probe | Release process exited `0`, but no `StatePoller stopped`, channel stopped, or `MIDIPortManager stopped` markers appeared. |
| `docs/ARCHITECTURE.md` | `245` | Claims orderly signal shutdown. |

Why this blocks release:

The cleanup path exists but signal termination does not execute it. Production supervisors normally use signals. A clean exit code without cleanup is not sufficient.

Required gate:

| Gate | Required proof |
|---|---|
| Signal triggers async coordinated shutdown | Real `SIGTERM` and `SIGINT` process probes show poller, channels, and port manager stopped before exit. |
| Exit code and timeout semantics defined | Forced kill timeout documented and tested. |
| Docs match implementation | Architecture and security docs no longer overstate graceful shutdown. |

### RB-4: Release provenance is not enterprise fail-closed

Severity: P0  
Status: open  
Production impact: production releases can still be ADHOC and non-notarized.

Evidence:

| File | Lines | Problem |
|---|---:|---|
| `.github/workflows/release.yml` | `41-54` | Missing signing cert selects `mode=adhoc` instead of failing production release. |
| `.github/workflows/release.yml` | `130-154` | ADHOC artifact verify path remains a release path. |
| `.github/workflows/release.yml` | `170-183` | `arm64` tarball copied from universal tarball in CI path; naming needs strict matrix proof. |
| `Scripts/release.sh` | `1-6` | Manual release script is explicitly "one-command ADHOC release." |
| `Scripts/release.sh` | `68-94` | Builds arm64 local binary, ADHOC signs, and writes `team_id:"ADHOC"`. |
| `Scripts/release.sh` | `80-83` | Copies arm64 tarball to `LogicProMCP-macOS-universal.tar.gz`. |
| `Formula/logic-pro-mcp.rb` | `9-21` | Formula comments describe arm64-native and universal alias ambiguity. |
| `SECURITY.md` | `111-120`, `170-184` | Security model admits current ADHOC mode and skipped Gatekeeper. |

Why this blocks release:

Enterprise release policy cannot treat ADHOC artifacts as production. SHA256 and ad-hoc codesign are useful integrity checks, but they are not Developer ID notarization and do not satisfy Gatekeeper/provenance requirements.

Required gate:

| Gate | Required proof |
|---|---|
| Production tags require notarization secrets | Release workflow fails if Developer ID/notary secrets are absent. |
| ADHOC clearly marked non-production | Manual script cannot publish production-looking artifacts. |
| Architecture names match binary slices | `file`, `lipo -info`, checksums, release metadata, Formula, README, and docs all agree. |
| Gatekeeper proof | Notarized release artifact passes `spctl --assess --type execute` on a clean host. |

### RB-5: E2E harness integrity is insufficient for release attestation

Severity: P1  
Status: open  
Production impact: current E2E assets can miss bugs or report false confidence.

Evidence:

| File | Lines | Problem |
|---|---:|---|
| `Scripts/live-e2e-test.py` | `16-27` | Defaults to debug binary. |
| `Scripts/live-e2e-test.py` | `491-515` | Treats mixer mutations as "dispatches" and accepts missing params as a response. |
| `Scripts/live-e2e-test.py` | `630-642` | Navigation checks mostly require content, not effect. |
| `Scripts/live-e2e-test.py` | `820-848` | Stress sections count response success without proving DAW side effects. |
| `Scripts/live-e2e-test.sh` | `31-33` | Short-lived stdin pipe produces empty responses in fresh run. |
| `Scripts/live-e2e-test.sh` | `32` | Uses `timeout`, which is not stock macOS. |
| Fresh shell run | `0/29` pass | Entire shell harness is currently unusable. |

Why this blocks release:

For commercial readiness, the harness must distinguish protocol response, command routing, and actual Logic Pro side effects. Current live tests mix those categories.

Required gate:

| Gate | Required proof |
|---|---|
| Release binary default | Harness runs the built release artifact by default or requires explicit artifact path. |
| Effect-proof categories | Mutating tests verify state change/readback where introspection exists. |
| Honest skips | Environment-gated tests must skip with precondition metadata, not silently pass weak checks. |
| Raw artifacts | Store JSON-RPC transcript, stderr, Logic version, macOS version, locale, artifact hash, and permission state. |

### RB-6: Install/uninstall rollback is not non-interactive-safe enough

Severity: P1  
Status: open  
Production impact: MDM or CI uninstall can partially remove artifacts and exit non-zero.

Evidence:

| File | Lines | Problem |
|---|---:|---|
| `Scripts/install-keycmds.sh` | `40` | Backup glob includes `*.plist` and `*.logickeycommands`, not `.logikcs`. |
| `Scripts/uninstall-keycmds.sh` | `37-49` | If `AUTO_RESTORE` is not set, script prompts with `read` under `set -euo pipefail`. |
| Fresh temp uninstall without auto-restore | Exit `1` after removing binary, approval store, and staged preset. |
| Fresh temp uninstall with auto-restore | Exit `0`, but only covered `*.plist` and `*.logickeycommands` backup set. |
| `README.md` | `100` | Says installer "installs the Key Commands preset" although Logic 12.2 path is reference/manual MIDI Learn. |
| `Scripts/install.sh` | `207-213` | Echoes "Key Commands preset installed" after staging reference file. |

Why this matters:

Enterprise rollout requires deterministic non-interactive install and rollback. Partial uninstall with exit `1` is not acceptable for fleet automation.

Required gate:

| Gate | Required proof |
|---|---|
| Non-interactive uninstall mode | No prompt or prompt-safe default in non-TTY contexts. |
| `.logikcs` coverage decision | Either backup/restore `.logikcs` or document why it is intentionally excluded. |
| Wording corrected | Installer says "mapping reference staged" unless an actual import/binding occurs. |
| Clean-host rehearsal | Install, setup, uninstall, rollback validated from a fresh macOS account. |

## High Findings

### H-1: Project audit log says `executed` before validation and confirmation

Severity: P1  
Evidence: `Sources/LogicProMCP/Dispatchers/ProjectDispatcher.swift:36-38` logs `[AUDIT] project.<command> executed` before param validation and confirmation gates. Fresh `EndToEndTests` and commercial suites printed `project.open executed` for invalid/missing paths.

Impact: audit records can overstate what happened. For enterprise audit, `confirmation_required`, `rejected`, `validated`, and `executed` must be distinct.

Required fix: move execution audit after confirmed route execution and add separate audit events for rejection and confirmation requirement.

### H-2: `goto_marker` cold-cache fallback is not target-faithful

Severity: P1  
Evidence: `Sources/LogicProMCP/Dispatchers/NavigateDispatcher.swift:29-80` documents that cache miss with index falls back to legacy `nav.goto_marker` key command, which advances marker pointer rather than targeting the requested index.

Impact: caller intent `goto_marker { index: N }` can become "go to next marker" when cache is cold. For production, target-specific commands should return uncertainty or fail closed rather than perform a different mutation.

Required fix: make cold-cache target-specific navigation return State B/State C unless exact target resolution is available.

### H-3: Public docs materially drift from current runtime

Severity: P1  
Evidence:

| File | Lines | Drift |
|---|---:|---|
| `README.md` | `15` | Badge says `1019+` tests, current fresh full run is `1083`. |
| `README.md` | `84-95` | One-line installer URLs pin `v3.1.1` while current version is `3.2.0`. |
| `README.md` | `188-190` | Says `1059` tests and prior reviews converged to `PROCEED`; current verdict is hard no-go. |
| `docs/ARCHITECTURE.md` | `28`, `65`, `94`, `162` | Still says `5s` AX polling. |
| `Sources/LogicProMCP/Server/ServerConfig.swift` | `27-35` | Actual interval is `3` seconds. |
| `docs/TROUBLESHOOTING.md` | `269-276` | Still says wait up to `5` seconds for cache update. |
| `docs/API.md` | `188`, `202` | `record_sequence` still describes old `100ms x 20 = 2s` cache polling. |
| `docs/API.md` | `366-388` | Marker docs still mix marker ruler language with Logic 12.2 marker-list reality. |
| `docs/API.md` | `455-456` | Project source freshness still says `5` seconds. |

Impact: operators and MCP clients will make decisions from stale contracts.

Required fix: regenerate docs from current runtime behavior and split historical release notes from current operational contract.

### H-4: CI coverage gate is disabled

Severity: P1  
Evidence: `.github/workflows/ci.yml:27-65` titles the step "gate disabled", uses `set +e`, and ends with unconditional `exit 0`.

Impact: coverage regression is not a merge blocker. This is especially dangerous because live OS integration surfaces are already weakly covered.

Required fix: separate report-only diagnostics from enforced thresholds and re-enable a meaningful gate.

### H-5: Swift Testing dependency is stale for current toolchain

Severity: P2  
Evidence: `Package.swift:15`, `Package.swift:34`, and test runs emit repeated deprecation warnings: Swift Testing is now included in Swift 6 toolchain and the package dependency should be removed.

Impact: warning volume hides real warnings and makes warning-as-error policy impractical. Prior project memory notes that removing it once failed due `_TestingInternals`, so this should be handled as a toolchain migration task, not a casual one-line removal.

Required fix: define the supported Xcode/Swift matrix, then remove or pin `swift-testing` in a way that passes the matrix without deprecation spam.

### H-6: AX helper force casts are not fully hardened

Severity: P2  
Evidence: most AXValue casts are guarded, but `Sources/LogicProMCP/Accessibility/AXHelpers.swift:209-226` force casts raw AX attributes without `CFGetTypeID` checks.

Impact: malformed, changing, or mocked AX attributes can crash instead of returning nil. This is lower severity than the write-path issues because the specific attributes are normally AXValue, but enterprise-grade UI automation should not trust AX shape blindly.

Required fix: use the same guarded pattern already present in `LibraryAccessor`, `PluginInspector`, `AXLogicProElements`, and parts of `AccessibilityChannel`.

## Strengths

The project has real strengths that should be preserved:

| Area | Evidence |
|---|---|
| Full deterministic test suite | `1083` tests pass under `swift test --no-parallel`. |
| In-process E2E breadth | `EndToEndTests` has `96` passing tests across tools/resources/lifecycle/concurrency. |
| Safety utility coverage | `AppleScriptSafety`, destructive policy, path validation, and MIDI input validation are materially better than typical automation projects. |
| Honest Contract direction | State A/B/C language is a strong design direction where consistently applied. |
| Installer pin policy | `Scripts/install.sh` fails closed without SHA256 and Team ID pins by default. |
| Version consistency tests | Version consistency is tested across several packaging artifacts. |

These strengths do not override the blockers. They indicate that the project is fixable, not releasable.

## Production Readiness Gate

The following must be true before the next production-ready claim:

| Gate | Required evidence |
|---|---|
| Mutating command safety | Every write command rejects missing, invalid, ambiguous, or unverified targets with tests proving no route executed. |
| Live stdio parity | Release artifact launched as stdio under MCP client has the same Logic, permission, channel, and CoreMIDI visibility as direct launch. |
| Signal cleanup | Real `SIGTERM` and `SIGINT` probes show orderly poller/channel/port shutdown before exit. |
| Notarized release | Production tags cannot publish ADHOC artifacts; notarized artifact passes `codesign`, `spctl`, install, and first-run on clean host. |
| E2E harness repair | Python harness defaults to release artifact and separates protocol, route, and effect-proof tests. Shell harness fixed or deleted. |
| Install/rollback rehearsal | Clean account, Homebrew tap, manual installer, uninstall, auto-restore, and non-interactive rollback all produce raw logs. |
| CI enforcement | Build, tests, coverage threshold, script lint, formula audit/test, and release validation are blocking checks. |
| Docs sync | README, API, architecture, troubleshooting, setup, maintainers, security, and live-verify docs match current runtime and current verdict. |
| Audit semantics | Audit logs distinguish rejected, confirmation-required, and executed operations. |
| Coverage risk closure | Accessibility, ProcessUtils, AXMouseHelper, LibraryAccessor, PluginInspector, and live harness gaps have targeted tests or documented manual certification. |

## Required E2E Matrix Before Commercialization

The current E2E work is not enough. The minimum acceptable matrix:

| Dimension | Required cases |
|---|---|
| Launch topology | Terminal TTY, MCP stdio from Claude Code, shell pipe, launch agent/supervisor if supported. |
| macOS privacy | Fresh permissions, denied permissions, granted Accessibility only, granted Automation only, both granted. |
| Logic state | Not installed, installed but closed, running no document, running unsaved document, running saved project, minimized, modal dialog, plugin window occlusion. |
| MIDI/CoreMIDI | No virtual ports, ports created, ports visible in Logic, MCU registered, MCU missing, Scripter missing, KeyCmd manual approval missing. |
| Mutating commands | Missing target, invalid target, valid target, stale cache, unverified selection, readback mismatch, idempotent same-value write. |
| Project lifecycle | `new`, `open`, `save_as`, `close`, `quit`, confirmation missing, confirmation true, invalid paths, network/external volumes if supported. |
| Markers | Empty project, marker list closed, marker list open, index lookup, name lookup, cold cache, non-canonical position, fallback/unknown provenance. |
| Library/plugins | Library panel closed/open, disk scan, AX scan, path resolve, load success, readback mismatch, plugin Setting popup absent/present. |
| Shutdown | EOF, `SIGTERM`, `SIGINT`, repeated signal, timeout, restart after signal, port cleanup visible. |
| Install | Homebrew tap, manual installer with out-of-band pins, same-origin opt-in, missing pins, wrong SHA, wrong Team ID, ADHOC, notarized. |
| Rollback | Non-interactive uninstall, auto-restore, no backup, backup present, `.plist`, `.logickeycommands`, `.logikcs`, approval store removal, Claude deregistration. |

## Residual Blind Spots

These areas remain unproven after this review:

| Area | Status |
|---|---|
| Clean-host Homebrew install | Not completed because formula test was rejected outside tap. |
| Notarized release artifact | Not available in this workspace. |
| Gatekeeper on published artifact | Not proven. |
| Real Logic project mutation effect proof | Live environment lacked a validated open project and stable permissions under stdio. |
| Multi-version Logic matrix | Logic 11.x, 12.0/12.1, 12.2, and future versions not covered in fresh run. |
| Locale matrix | Current fresh live run did not validate broad locale behavior. |
| Long-running stability | No multi-hour soak with live Logic and repeated mutations. |
| MDM/fleet deployment | Not rehearsed. |
| Full security review of release secrets | Not possible locally. |

## Final Decision

Final verdict remains `HARD NO-GO`.

This project has a strong foundation, but it is not yet commercial-grade. The next work should not be more broad claims or more response-only tests. It should close the P0 write-safety defects, repair stdio live launch behavior, implement real signal cleanup, make production releases notarized-only, fix E2E harness false positives, and regenerate docs from the actual runtime contract.

Until those gates pass with fresh evidence, do not mark the repository, artifact, Formula, or README as production ready.
