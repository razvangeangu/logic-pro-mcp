# Bug Label Triage - 2026-06-19

Scope: GitHub issues in `MongLong0214/logic-pro-mcp` with the `bug` label, reviewed after the v3.6.0 release and PR #54 / issue #59 resolution.

Source checks:
- `gh issue list --label bug --state open --limit 200`
- `gh issue list --label bug --state closed --limit 200`
- `gh issue view 33..60 --json number,title,state,labels,body,comments,updatedAt,url`
- Local code/docs spot checks in `Sources/LogicProMCP`, `Tests/LogicProMCPTests`, and `docs/TROUBLESHOOTING.md`
- Targeted tests:
  - `swift test --filter 'AccessibilityChannelValidatedMIDIImportPath|ResourceSchemaTests/testTransportStateResourceRefreshesLiveStateBeforeServingCache'`
  - `swift test --filter testTransportStateResourceRefreshesLiveStateBeforeServingCache`

Result count:
- Open bug-labeled issues: 26
- Closed bug-labeled issues: 1 (`#59`)
- Recommended canonical bug leaves before targeted retest: 16
- Final open bug leaves after targeted retest: 17
- Recommended merge/close/relabel/retest candidates: 10 open issues plus the already-closed `#59`

Execution update:
- GitHub cleanup was executed after operator approval on 2026-06-19.
- Closed as resolved/stale: `#33`.
- Closed as duplicates/folded into canonical issues: `#36 -> #47`, `#41 -> #48`, `#52 -> #45`, `#53 -> #35/#58`, `#57 -> #40`.
- Closed as resolved demo incident: `#50`; product roots remain in `#43` and `#44`.
- Reclassified open non-bug backlog: `#46` now `enhancement`; `#60` now `enhancement`.
- Retested but left open: `#48` and `#56`. `play` returned verified State A and post-stop resource readback refreshed to `isPlaying=false` / `isRecording=false`, but product `stop` still returned `verified:false` / `reason:readback_unavailable`; `record` did not complete cleanly in the targeted probe.
- Final open bug-labeled issues after cleanup: 17 (`#34`, `#35`, `#37`, `#38`, `#39`, `#40`, `#42`, `#43`, `#44`, `#45`, `#47`, `#48`, `#49`, `#51`, `#55`, `#56`, `#58`).
- Closed bug-labeled issues after cleanup: 7 (`#33`, `#36`, `#41`, `#52`, `#53`, `#57`, `#59`). `#50` is closed with the `bug` label removed.

## Keep As Canonical Bug Leaves

These still represent concrete, currently useful bug leaves or demo/live-harness failures. They should remain open until fixed or disproved by fresh live evidence.

| Canonical issue | Keep because | Related issues to fold in |
| --- | --- | --- |
| `#34` Track rename fails in live Logic UI | No current fix evidence found for locating/writing the track name field and verifying through live track readback. | None |
| `#35` Track creation commands are not verified | Still the right canonical issue for `create_*` returning attempted/unverified instead of observed track-count/type deltas. | Fold `#53` timeout/pollution details into this issue. |
| `#37` Region readback fails in real Logic UI sessions | Still blocks post-write proof that MIDI/audio regions landed on the intended track and range. | Helps explain `#42`. |
| `#38` Plugin and insert inventory cannot locate mixer/insert subtree | Still a real workflow blocker unless the product intentionally requires the user to expose the Mixer first. Keep unless reclassified as supported limitation. | Related to verified-plugin workflows but not fully replaced by PR #24/#54. |
| `#39` Mixer volume/pan writes are unverified or wrong-strip-risky | Current docs still describe State B when MCU echo and AX readback are unavailable; pan remains relative/non-idempotent. | None |
| `#40` Key-command-backed edit/navigation commands lack readback | Keep, but narrow it to commands that still lack independent readback. `goto_position` and metronome should be rechecked because current code has stronger readback paths. | Fold `#57` playhead-stale symptom here if not keeping a separate demo-harness issue. |
| `#42` `record_sequence` is not reliable enough | User-facing composition API remains blocked by import/readback/playhead proof. | Depends on `#37`, `#49`, and `#40/#57`. |
| `#43` Instrument/patch assignment is not verified | Still no evidence of a readback-verified target-track patch/instrument workflow for composition demos. | Fold the unresolved root of `#50` here. |
| `#44` Demo audio provenance must be real Logic output or verified bounce | Keep as demo/release credibility guard. v23/v24 prove the acceptable bounce path, but the guard remains useful to prevent guide-audio regressions. | Fold old guide-audio incident `#50` here. |
| `#45` Fresh Logic project bootstrap is brittle | Keep as canonical fresh-session / clean-baseline harness issue. | Fold `#52` polluted-session evidence here. |
| `#47` Tempo write can fail to locate or exactly verify tempo | Use this as the canonical tempo issue. | Fold `#36` overshoot/readback-mismatch case here. |
| `#48` Transport play/record/stop lookup and verified action path | Use as canonical transport-action issue, but re-test because current control-bar checkbox path likely fixed part of it. | Fold `#41`; compare with `#56`. |
| `#49` MIDI import rejects valid managed temp paths | Still valid. `AccessibilityChannel.validatedMIDIImportPath` is hardened, but dispatcher-side validation still checks raw `/tmp/LogicProMCP/` prefix and lacks a `/private/tmp` regression. | Supports `#42`. |
| `#51` `set_cycle_range` cannot set numeric locators | Still valid. Current code can return unverified fallback or unsupported text when AX locator fields are absent. | Related to bounce/export workflows. |
| `#55` `arm` / `arm_only` reports outer success while nested readback is unverified | Still valid because it is a distinct nested-contract classification bug for record-enable state. | None |
| `#56` Transport state / Stop verification can remain untrusted | Targeted retest showed fresh post-stop resource readback, but product `stop` still returned `verified:false` / `reason:readback_unavailable`, and the `record` probe did not complete cleanly. | Compare with `#48` transport action reliability and `#40` playhead/readback gating. |
| `#58` Free Tempo Recording modal interrupts fresh live-record captures | Still valid as a first-class modal detection/recovery problem for demo/live harnesses. | Related to `#45` and `#53`, but modal policy deserves its own issue. |

## Merge Or Close Candidates

These are either stale, duplicate, incident-specific, or not a leaf bug.

| Issue | Recommendation | Reason |
| --- | --- | --- |
| `#33` Track resource returns empty after visible live track creation | Close as resolved/duplicate of `#59` after adding a short resolution note. | PR #54 / `#59` fixed the Logic 12.2 track-header readback root class; docs already record current `logic://tracks` returning real `ax_live` rows. |
| `#36` Tempo setting can overshoot and still report success | Merge into `#47`, then close duplicate. | Same feature surface; current code returns State B on mismatch, while `#47` is the better canonical fresh-UI tempo issue. |
| `#41` Transport stop AX lookup fails | Merge into `#48`, then close duplicate. | Stop is one action inside the broader play/record/stop transport-action issue. |
| `#46` Video rendering pipeline had non-product failures | Remove `bug` label or close if no standalone demo-renderer backlog is desired. | This is demo-process quality, not a product bug. Current demos already use ffprobe/blackdetect/contact sheet/provenance evidence. |
| `#50` Guide audio misrepresents visible Logic instrument state | Close as resolved incident; keep root risks in `#43` and `#44`. | v17 was excluded; v18 removed audio; v23/v24 established verified-bounce path. |
| `#52` Reusing polluted Logic sessions hides fresh-project truth | Merge into `#45`, then close duplicate. | Same fresh-session/bootstrap boundary; `#45` is the better canonical harness issue. |
| `#53` `create_instrument` timeout can pollute fresh capture track numbering | Merge into `#35`, with modal-specific pieces in `#58`; then close duplicate. | Specific failure mode of unverified/timeout track creation plus modal handling. |
| `#57` Unverified go-to-beginning can record at stale high bars | Merge into `#40` or `#42`, then close duplicate if the playhead verification acceptance criteria are copied. | It is a concrete symptom of unverified `goto_position` plus record-sequence/live-record gating. |
| `#60` Locale-agnostic UI automation epic | Keep as epic, remove `bug` label. | Valid umbrella, but not a leaf bug. It should organize bugs, not count as one. |

## Retest Before Closing

These look partially or likely fixed by v3.6.0 code, but should not be closed without an issue-specific live probe.

| Issue | Current evidence | Required close check |
| --- | --- | --- |
| `#48` Transport play/record/stop | Current code now uses Logic 12 control-bar checkbox lookup, mouse/AXPress/AXConfirm strategies, and readback before State A. | Fresh Logic project: `record -> state`, `stop -> state`, `play -> state`, `stop -> state`; verify no `element_not_found` and no stale `isPlaying/isRecording`. |
| `#56` Transport state stale after visible Stop / MCP Stop | Current resource path refreshes `logic://transport/state` through live `transport.get_state`; targeted unit test `testTransportStateResourceRefreshesLiveStateBeforeServingCache` passes. A 2026-06-19 live probe showed fresh post-stop resource readback but did not satisfy product stop/record verification. | Keep open until product `stop` returns verified State A with observed `isPlaying=false` / `isRecording=false`, and the record/stop roundtrip completes cleanly. |
| `#40` Key-command-backed commands | `goto_position` has dialog/slider readback paths; transport toggles use control-bar readback for some controls. | Re-run the exact affected commands and remove resolved subitems from the issue body/comment. Keep only the commands still State B. |

## Suggested GitHub Cleanup Order

1. Add a short triage comment to each merge target explaining the canonical issue.
2. Close clear duplicates/incidents: `#33`, `#36`, `#41`, `#50`, `#52`, `#53`, and likely `#57` after copying acceptance criteria.
3. Remove `bug` from `#60`; keep it as the umbrella epic.
4. Remove `bug` from `#46` or close it, depending on whether demo-renderer automation remains in scope.
5. Run targeted live probes for `#48/#56/#40`; close only if the exact issue acceptance criteria pass.
6. Leave the 17 canonical leaves open and group work around:
   - Track/arrangement verification: `#34`, `#35`, `#37`, `#42`, `#43`, `#55`
   - Tempo/transport/playhead: `#40`, `#47`, `#48`, `#51`, `#56`
   - Mixer/plugin verification: `#38`, `#39`
   - Demo/live-harness credibility: `#44`, `#45`, `#58`
   - MIDI import validation: `#49`
