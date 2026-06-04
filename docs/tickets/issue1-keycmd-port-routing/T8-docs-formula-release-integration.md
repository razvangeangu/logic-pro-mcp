# T8: Docs + Homebrew formula `xcode` removal + release.sh Issue #1 automation + version bump

> Historical record (2026-06-05 docs refresh): latest production-readiness and live E2E evidence is in `README.md`, `CHANGELOG.md`, and `docs/live-verify-v3.4.5-rc5.md`; this file remains preserved implementation context.

**PRD Ref**: PRD-issue1-keycmd-port-routing > §3 AC-3.1-3.6, AC-4.1-4.5, §9.1, §10.2 R8
**Priority**: P1 (High — final integration step + user communication)
**Size**: L (4-8h — 4 docs files + Formula + release.sh + CHANGELOG + version bump + tool description)
**Status**: Todo
**Depends On**: T1-T7 (all code changes integrated before docs/release)

---

## 1. Objective
Integrate all Issue #1 user-facing changes:
- Remove misleading `.plist` Import guidance from SETUP.md / TROUBLESHOOTING.md / Scripts/install.sh / Scripts/install-keycmds.sh / Scripts/keycmd-preset.plist headers
- Add Manual MIDI Learn 2-example step-by-step + audited coverage matrix
- Remove Homebrew formula `depends_on xcode` + add comment explicitly noting ADHOC binary path
- Add `gh issue comment 1` + `gh issue close 1` automation to release.sh (with re-open spam guard)
- CHANGELOG v3.1.5 entry (BREAKING table #1 + table #2 + Issue #1 closure link)
- Version bump 3.1.4 → 3.1.5 (manifest.json, ServerConfig.swift, Formula, README, install.sh)
- Tool description (MIDIDispatcher + TrackDispatcher) inline "channel: 1..16 (1-based)" + "port: midi/keycmd default midi"

## 2. Acceptance Criteria
- [ ] AC-1: `docs/SETUP.md` §<MIDIKeyCommands section> contains 0 `.plist` Import instructions. Includes 2 Manual MIDI Learn examples (Edit > Undo + Track > New Audio Track) + time-required note + audited coverage matrix
- [ ] AC-2: `docs/TROUBLESHOOTING.md` includes honest guidance about Logic 12.2 `.plist` import greyed-out behavior + migration path for users who followed SETUP prior to v3.1.4
- [ ] AC-3: `Scripts/install.sh` + `install-keycmds.sh` + `keycmd-preset.plist` headers all have misleading "Import" instructions removed
- [ ] AC-4: `Formula/logic-pro-mcp.rb` `depends_on xcode: ["15.0", :build]` line removed + comment added
- [ ] AC-5: `brew audit --strict --new-formula Formula/logic-pro-mcp.rb` passes (local verification)
- [ ] AC-6: `brew style Formula/logic-pro-mcp.rb` passes
- [ ] AC-7: `Scripts/release.sh` gains Issue #1 auto comment + close step — `gh issue view 1 --json state` check: only executes when OPEN (skips if CLOSED, R8)
- [ ] AC-8: `CHANGELOG.md` gains v3.1.5 entry (both BREAKING tables + full change summary + Issue #1 closure link)
- [ ] AC-9: Version bump in 5+ files (manifest.json, ServerConfig.swift, Formula, README, install.sh, LogicProServerTransportTests.swift) from 3.1.4 → 3.1.5
- [ ] AC-10: Tool description (`MIDIDispatcher.description`) inline "port: midi/keycmd default midi; channel: 1..16 (1-based)" + `TrackDispatcher.description` "channel 1-based since v3.1.5"
- [ ] AC-11: Release notes file (used by release.sh) includes BREAKING + audited matrix link + Issue #1 close notice
- [ ] AC-12 (Phase 4 Loop 1 strategist+guardian+boomer consensus): **Live Verification gate** — PRD §8.4 Scenario 1 (Logic Controller Assignments → Learn Mode captures `LogicProMCP-KeyCmd-Internal` input) + Scenario 2 (channel:16 send → Logic UI shows Ch 16) + Scenario 4 (`brew install logic-pro-mcp` on CLT-only host passes) are **release-blockers**. Confirm all 3 scenarios PASS in Isaac's environment before the release commit. Record PASS evidence (screenshot or health.detail capture) in `docs/live-verify-v3.1.6.md` or the release notes evidence section.

## 3. TDD Spec (Red Phase)

### 3.1 Test Cases

| # | Test Name | Type | Description | Expected |
|---|-----------|------|-------------|----------|
| 1 | `testServerVersionMatchesPackagingArtefacts` | Unit (extend) | manifest.json + ServerConfig + Formula + README + install.sh all read 3.1.5 | regex match |
| 2 | `testStartupBannerVersionV315` | Unit (extend) | LogicProServerTransportTests "v3.1.5" | match |
| 3 | `testToolDescriptionContainsPortAndChannelInfo` | Unit | inspect `MIDIDispatcher.description` | "port:" + "1-based" substrings |
| 4 | `testTrackDispatcherDescriptionIncludesChannelInfo` | Unit | `TrackDispatcher.description` | "channel 1-based since v3.1.5" |
| 5 | (manual) brew audit pass | Local | `brew audit --strict --new-formula` | exit 0 |
| 6 | (manual) brew style pass | Local | `brew style` | exit 0 |
| 7 | (manual) release.sh dry-run | Local | `DRY_RUN=1 Scripts/release.sh v3.1.5` | gh comment + close steps logged |
| 8 | (manual) docs review | Phase 6 | SETUP.md / TROUBLESHOOTING.md follow-along | 1+ binding succeeded |

### 3.2 Test File Location
- `Tests/LogicProMCPTests/LogicProServerTransportTests.swift` (extend 1, 2)
- `Tests/LogicProMCPTests/MIDIDispatcherDescriptionTests.swift` (NEW 3)
- `Tests/LogicProMCPTests/TrackDispatcherDescriptionTests.swift` (NEW or extend 4)

### 3.3 Mock/Setup Required
- None (static string inspection)

## 4. Implementation Guide

### 4.1 Files to Modify
| File | Change Type | Description |
|------|------------|-------------|
| `docs/SETUP.md` | Modify | §MIDIKeyCommands rewrite, manual learn 2 examples, audited matrix |
| `docs/TROUBLESHOOTING.md` | Modify | Logic 12.2 import gray-out honest guidance + migration |
| `Scripts/install.sh` | Modify | Remove import guidance at ~line 235 + version bump |
| `Scripts/install-keycmds.sh` | Modify | Correct output messages |
| `Scripts/keycmd-preset.plist` | Modify | Correct header comment (XML comment) |
| `Formula/logic-pro-mcp.rb` | Modify | Remove `depends_on xcode` + add comment + version bump |
| `Scripts/release.sh` | Modify | Add Issue #1 auto comment + close steps (gh issue view check) |
| `CHANGELOG.md` | Modify | Add v3.1.5 entry (all changes integrated) |
| `manifest.json` | Modify | version + download_url bump |
| `Sources/LogicProMCP/Server/ServerConfig.swift` | Modify | serverVersion bump |
| `README.md` | Modify | test count + version badge |
| `Sources/LogicProMCP/Dispatchers/MIDIDispatcher.swift` | Modify | description string |
| `Sources/LogicProMCP/Dispatchers/TrackDispatcher.swift` | Modify | description string |
| Tests | Modify | version-related expectations |

### 4.2 Implementation Steps (Green Phase)
1. Rewrite SETUP.md (audited matrix + 2 manual learn examples) — refer to PRD §3 AC-3.x
2. Correct TROUBLESHOOTING.md
3. Fix `Scripts/install*.sh` + `keycmd-preset.plist`
4. Remove Formula `depends_on xcode` + add comment
5. Add Issue #1 automation steps to release.sh:
   ```bash
   ISSUE_STATE=$(gh issue view 1 --json state -q .state 2>/dev/null || echo "UNKNOWN")
   if [ "$ISSUE_STATE" = "OPEN" ]; then
       gh issue comment 1 --body "Released in $VERSION — see release notes."
       gh issue close 1
   fi
   ```
6. Add CHANGELOG v3.1.5 entry (BREAKING table #1 + #2 + change summary)
7. Bump version in 5+ files simultaneously
8. Update tool description strings
9. Local `brew audit` / `brew style` verification
10. Full `swift test --no-parallel` pass verification

### 4.3 Refactor Phase
- Evaluate making SETUP.md table generation a codebase-driven script (PATTERN_LOG: matrix accuracy is a recurring issue)

## 5. Edge Cases
- EC-1: GitHub Issue #1 already closed by another user → release.sh OPEN check skips gracefully
- EC-2: `brew audit` failure requires additional Formula corrections — catch with pre-run dry-run
- EC-3: docs follow-along failure — re-correct in Phase 6 strategist review and re-verify

## 6. Review Checklist
- [ ] Red: 4 unit tests FAILED + 4 manual checks not performed
- [ ] Green: 4 unit tests PASSED + 4 manual checks passed
- [ ] AC 11 items satisfied
- [ ] T1-T7 all changes integration verified (full `swift test --no-parallel` PASS)
- [ ] Existing release.sh dry-run works correctly
- [ ] docs follow-along 1 run PASS
- [ ] BREAKING change user communication via 5 channels (CHANGELOG / Release notes / Issue #1 / Tool description / health detail) all consistent
