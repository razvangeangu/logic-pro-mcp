# T4: ChannelRouter `bypassReadinessOps` + available==false `.portUnavailable` branch

> Historical record. Current stable evidence is in `README.md`, `CHANGELOG.md`, and `docs/live-verify-v3.7.0.md`; previous stable evidence remains in `docs/live-verify-v3.6.0.md`; this file remains preserved implementation context.

**PRD Ref**: PRD-issue1-keycmd-port-routing > §3 AC-1.7, §4.1 step 6-7, §5 E7
**Priority**: P0 (Blocker — core fix for Issue #1, breaks the KeyCmd seeding chicken-and-egg lock-in)
**Size**: M (2-4h)
**Status**: Todo
**Depends On**: T1 (HonestContract `.portUnavailable`)

---

## 1. Objective
Introduce `bypassReadinessOps: Set<String>` to the ChannelRouter readiness gate so the `midi.*.keycmd` 7 ops can pass through manual_validation_required channels. Also: when `available: false` (virtual port not created), return `.portUnavailable` HC envelope directly to block router fallback wrapping.

## 2. Acceptance Criteria
- [ ] AC-0 (visibility): `bypassReadinessOps` Set is `internal static let` (for test access). `routingTable` also `internal` (T5 invariant test dependency). Access via `@testable import LogicProMCP`.
- [ ] AC-1: `ChannelRouter` gains `bypassReadinessOps: Set<String>` static field with 7 keys registered (`midi.send_cc.keycmd`, `midi.send_note.keycmd`, `midi.send_chord.keycmd`, `midi.send_program_change.keycmd`, `midi.send_pitch_bend.keycmd`, `midi.send_aftertouch.keycmd`, `midi.play_sequence.keycmd`)
- [ ] AC-2: `route(operation:params:)` skips `ready` check when `bypassReadinessOps.contains(operation)`
- [ ] AC-3: Even bypass ops are blocked if `available: false` → `.portUnavailable` HC envelope returned directly
- [ ] AC-4: Standard readiness gate behavior unchanged for regular ops (existing `health.ready || allowManualValidationChannels`)
- [ ] AC-5: `.portUnavailable` envelope includes `hint: health.detail` + `extras: ["operation": op]`
- [ ] AC-6: `.portUnavailable` is in `terminalErrorCodes` so router does not wrap with `lastError` — returns immediately
- [ ] AC-7: Bypass working scenario: KeyCmd channel manual_validation_required (`available: true, ready: false`) + `midi.send_cc.keycmd` op → execute passes through → reaches MIDIKeyCommandsChannel.execute
- [ ] AC-8: Bypass not-working scenario: standard `midi.send_cc` (no suffix) op → existing readiness gate unchanged

## 3. TDD Spec (Red Phase)

### 3.1 Test Cases

| # | Test Name | Type | Description | Expected |
|---|-----------|------|-------------|----------|
| 1 | `testBypassReadinessOpsContainsAllSevenKeycmdOps` | Unit | Set membership for 7 expected keys | all true |
| 2 | `testBypassOpsRouteThroughManualValidationChannel` | Integration | mock channel `available:true, ready:false` + bypass op | execute called |
| 3 | `testBypassOpsRejectedWhenChannelUnavailable` | Integration | mock channel `available:false` + bypass op | `.portUnavailable` envelope returned |
| 4 | `testNonBypassOpUsesStandardReadinessGate` | Integration | `midi.send_cc` (no suffix) + ready:false channel | gate skips → next channel |
| 5 | `testPortUnavailableEnvelopeIncludesHintFromHealth` | Unit | health.detail in envelope hint | hint substring match |
| 6 | `testPortUnavailableEnvelopeIncludesOperationInExtras` | Unit | extras["operation"] == op key | match |
| 7 | `testPortUnavailableTerminalDoesNotFallthrough` | Integration | `.portUnavailable` returned → next channel not attempted | router exits immediately |
| 8 | `testRoutingTableInvariantBypassMatchesKeycmdSuffix` | Unit | all `^midi\..*\.keycmd$` routing keys in bypassReadinessOps + all bypassReadinessOps entries in routingTable (bidirectional invariant). **Run after T5 completion** (T5 adds 14 routingTable entries — Phase 4 Loop 1 tester P1) | invariant passes |
| 9 | `testBypassOpsDoesNotAffectOtherChannelsRouting` | Integration | core_midi/applescript standard op routing unaffected | regression |

### 3.2 Test File Location
- `Tests/LogicProMCPTests/ChannelRouterBypassReadinessTests.swift` (NEW)

### 3.3 Mock/Setup Required
- `MockChannel(available:Bool, ready:Bool, executeStub: ChannelResult)` pattern (reference existing ChannelRouterTests)
- `MockHealth(available:Bool, ready:Bool, detail:String)` 

## 4. Implementation Guide

### 4.1 Files to Modify
| File | Change Type | Description |
|------|------------|-------------|
| `Sources/LogicProMCP/Channels/ChannelRouter.swift` | Modify | bypassReadinessOps Set + route() readiness gate branch + available==false portUnavailable branch |
| `Tests/LogicProMCPTests/ChannelRouterBypassReadinessTests.swift` | Create | 9 tests |

### 4.2 Implementation Steps (Green Phase)
1. Add static field to `ChannelRouter`:
   ```swift
   static let bypassReadinessOps: Set<String> = [
       "midi.send_cc.keycmd",
       "midi.send_note.keycmd",
       "midi.send_chord.keycmd",
       "midi.send_program_change.keycmd",
       "midi.send_pitch_bend.keycmd",
       "midi.send_aftertouch.keycmd",
       "midi.play_sequence.keycmd",
   ]
   ```
2. Inside `route(operation:params:)` readiness gate branch (near line ~282):
   ```swift
   let isBypass = Self.bypassReadinessOps.contains(operation)
   guard health.available else {
       // available:false blocks regardless of bypass or standard
       if isBypass {
           return .error(HonestContract.encodeStateC(
               error: .portUnavailable,
               hint: health.detail,
               extras: ["operation": operation]
           ))
       }
       // Standard op: accumulate lastError
       lastError = "Channel \(channelID.rawValue) not available"
       continue
   }
   guard isBypass || health.ready || ServerConfig.allowManualValidationChannels else {
       continue
   }
   // execute
   ```
3. terminalErrorCodes branch already registered in T1 → works automatically
4. Run tests → all 9 PASS

### 4.3 Refactor Phase
- Consider auto-generating bypassReadinessOps from routingTable keys by suffix extraction. For v3.1.5 scope, keep explicit list (readability + invariant test prevents omissions)

## 5. Edge Cases
- EC-1: `health.available == nil` (health check failure) — verify `health` API spec for nil case → conservatively block + portUnavailable
- EC-2: bypass op with no routingTable mapping (typo etc.) — routingTable has no entry → existing "operation not handled" error (routingTable additions verified in T5)

## 6. Review Checklist
- [ ] Red: 9 tests FAILED confirmed
- [ ] Green: 9 PASSED
- [ ] AC 8 items satisfied
- [ ] Existing ChannelRouterTests: 0 regressions
- [ ] T1 (HonestContract `.portUnavailable`) dependency accurate
- [ ] bypassReadinessOps invariant test guarantees future maintenance safety
