# T8: Docs + Homebrew formula `xcode` 제거 + release.sh Issue #1 자동화 + version bump

**PRD Ref**: PRD-issue1-keycmd-port-routing > §3 AC-3.1-3.6, AC-4.1-4.5, §9.1, §10.2 R8
**Priority**: P1 (High — final integration step + user communication)
**Size**: L (4-8h — 4 docs files + Formula + release.sh + CHANGELOG + version bump + tool description)
**Status**: Todo
**Depends On**: T1-T7 (모든 코드 변경 통합 후 docs/release)

---

## 1. Objective
Issue #1 사용자 facing 변경사항 통합:
- SETUP.md / TROUBLESHOOTING.md / Scripts/install.sh / Scripts/install-keycmds.sh / Scripts/keycmd-preset.plist 헤더에서 misleading `.plist` Import 안내 제거
- Manual MIDI Learn 2개 예시 step-by-step + audited coverage matrix
- Homebrew formula `depends_on xcode` 제거 + 코멘트로 ADHOC binary path 명시
- release.sh에 `gh issue comment 1` + `gh issue close 1` 자동화 (재오픈 시 spam 방지)
- CHANGELOG v3.1.5 entry (BREAKING 표 #1 + 표 #2 + Issue #1 closure link)
- version bump 3.1.4 → 3.1.5 (manifest.json, ServerConfig.swift, Formula, README, install.sh)
- Tool description (MIDIDispatcher + TrackDispatcher) inline "channel: 1..16 (1-based)" + "port: midi/keycmd default midi"

## 2. Acceptance Criteria
- [ ] AC-1: docs/SETUP.md §<MIDIKeyCommands section>이 `.plist` Import 안내 0개. Manual MIDI Learn 2개 예시 (Edit > Undo + Track > New Audio Track) + 시간 소요 명시 + audited coverage matrix
- [ ] AC-2: docs/TROUBLESHOOTING.md에 Logic 12.2 `.plist` import 회색 처리 정직 안내 + v3.1.4 이전 SETUP 따라간 사용자 migration
- [ ] AC-3: Scripts/install.sh + install-keycmds.sh + keycmd-preset.plist 헤더 모두 misleading "Import" 안내 제거
- [ ] AC-4: Formula/logic-pro-mcp.rb의 `depends_on xcode: ["15.0", :build]` 라인 제거 + 코멘트 명시
- [ ] AC-5: `brew audit --strict --new-formula Formula/logic-pro-mcp.rb` 통과 (로컬 검증)
- [ ] AC-6: `brew style Formula/logic-pro-mcp.rb` 통과
- [ ] AC-7: Scripts/release.sh에 Issue #1 자동 comment + close step 추가 — `gh issue view 1 --json state` 로 OPEN 시만 동작 (CLOSED면 skip, R8)
- [ ] AC-8: CHANGELOG.md에 v3.1.5 entry 추가 (BREAKING 두 표 + 모든 변경 요약 + Issue #1 closure link)
- [ ] AC-9: Version bump 5 파일 (manifest.json, ServerConfig.swift, Formula, README, install.sh, LogicProServerTransportTests.swift) 3.1.4 → 3.1.5
- [ ] AC-10: Tool description (MIDIDispatcher.description) inline "port: midi/keycmd default midi; channel: 1..16 (1-based)" + TrackDispatcher.description "channel 1-based since v3.1.5"
- [ ] AC-11: release notes 파일 (release.sh가 사용)에 BREAKING + audited matrix link + Issue #1 close 안내
- [ ] AC-12 (Phase 4 Loop 1 strategist+guardian+boomer 합의): **Live Verification gate** — PRD §8.4 시나리오 1 (Logic Controller Assignments → Learn Mode capture로 `LogicProMCP-KeyCmd-Internal` 입력 캡처) + 시나리오 2 (channel:16 송신 → Logic UI Ch 16 표시) + 시나리오 4 (`brew install logic-pro-mcp` CLT-only host 통과)가 **release-blocker**. release commit 직전 Isaac 환경에서 3 시나리오 PASS 확인 후 release 진행. PASS 증거(screenshot 또는 health.detail capture)를 `docs/live-verify-v3.1.6.md` 또는 release notes evidence 섹션에 기록.

## 3. TDD Spec (Red Phase)

### 3.1 Test Cases

| # | Test Name | Type | Description | Expected |
|---|-----------|------|-------------|----------|
| 1 | `testServerVersionMatchesPackagingArtefacts` | Unit (확장) | manifest.json + ServerConfig + Formula + README + install.sh 모두 3.1.5 | regex match |
| 2 | `testStartupBannerVersionV315` | Unit (확장) | LogicProServerTransportTests "v3.1.5" | match |
| 3 | `testToolDescriptionContainsPortAndChannelInfo` | Unit | MIDIDispatcher.description 검사 | "port:" + "1-based" substrings |
| 4 | `testTrackDispatcherDescriptionIncludesChannelInfo` | Unit | TrackDispatcher.description | "channel 1-based since v3.1.5" |
| 5 | (manual) brew audit pass | Local | `brew audit --strict --new-formula` | exit 0 |
| 6 | (manual) brew style pass | Local | `brew style` | exit 0 |
| 7 | (manual) release.sh dry-run | Local | `DRY_RUN=1 Scripts/release.sh v3.1.5` | gh comment + close steps logged |
| 8 | (manual) docs review | Phase 6 | SETUP.md / TROUBLESHOOTING.md follow-along | 1+ binding 성공 |

### 3.2 Test File Location
- `Tests/LogicProMCPTests/LogicProServerTransportTests.swift` (확장 1, 2)
- `Tests/LogicProMCPTests/MIDIDispatcherDescriptionTests.swift` (NEW 3)
- `Tests/LogicProMCPTests/TrackDispatcherDescriptionTests.swift` (NEW 또는 확장 4)

### 3.3 Mock/Setup Required
- 없음 (정적 string 검사)

## 4. Implementation Guide

### 4.1 Files to Modify
| File | Change Type | Description |
|------|------------|-------------|
| `docs/SETUP.md` | Modify | §MIDIKeyCommands 재작성, manual learn 2 examples, audited matrix |
| `docs/TROUBLESHOOTING.md` | Modify | Logic 12.2 import gray-out 안내 + migration |
| `Scripts/install.sh` | Modify | line ~235 import 안내 제거 + version bump |
| `Scripts/install-keycmds.sh` | Modify | 출력 메시지 정정 |
| `Scripts/keycmd-preset.plist` | Modify | 헤더 주석 정정 (XML comment) |
| `Formula/logic-pro-mcp.rb` | Modify | depends_on xcode 제거 + 코멘트 + version bump |
| `Scripts/release.sh` | Modify | Issue #1 자동 comment + close 단계 (gh issue view check) |
| `CHANGELOG.md` | Modify | v3.1.5 entry 추가 (전 변경 통합) |
| `manifest.json` | Modify | version + download_url bump |
| `Sources/LogicProMCP/Server/ServerConfig.swift` | Modify | serverVersion bump |
| `README.md` | Modify | tests count + version badge |
| `Sources/LogicProMCP/Dispatchers/MIDIDispatcher.swift` | Modify | description string |
| `Sources/LogicProMCP/Dispatchers/TrackDispatcher.swift` | Modify | description string |
| Tests | Modify | version-related expectations |

### 4.2 Implementation Steps (Green Phase)
1. SETUP.md 재작성 (audited matrix + 2 manual learn examples) — PRD §3 AC-3.x 참조
2. TROUBLESHOOTING.md 정정
3. Scripts/install*.sh + keycmd-preset.plist 정정
4. Formula `depends_on xcode` 제거 + 코멘트 추가
5. release.sh에 Issue #1 자동화 단계:
   ```bash
   ISSUE_STATE=$(gh issue view 1 --json state -q .state 2>/dev/null || echo "UNKNOWN")
   if [ "$ISSUE_STATE" = "OPEN" ]; then
       gh issue comment 1 --body "Released in $VERSION — see release notes."
       gh issue close 1
   fi
   ```
6. CHANGELOG v3.1.5 entry (BREAKING 표 #1 + #2 + 변경 요약)
7. version bump 5+ 파일 동시
8. Tool description string 갱신
9. brew audit/style 로컬 검증
10. swift test --no-parallel 전체 통과 검증

### 4.3 Refactor Phase
- SETUP.md table generation을 codebase-driven script로 만들지 검토 (PATTERN_LOG: matrix accuracy 반복 issue)

## 5. Edge Cases
- EC-1: GitHub Issue #1이 이미 다른 사용자에 의해 close → release.sh가 OPEN check로 skip
- EC-2: brew audit 실패 시 Formula 추가 정정 필요 — 사전 dry-run으로 캐치
- EC-3: docs follow-along 실패 시 — Phase 6 strategist 리뷰에서 재정정 후 재검증

## 6. Review Checklist
- [ ] Red: 4 unit test FAILED + 4 manual checks 미수행
- [ ] Green: 4 unit test PASSED + 4 manual checks 통과
- [ ] AC 11건 충족
- [ ] T1-T7 모든 변경 통합 검증 (전체 swift test --no-parallel PASS)
- [ ] 기존 release.sh dry-run 정상 동작
- [ ] docs follow-along 1회 PASS
- [ ] BREAKING change 사용자 communication 5중 채널 (CHANGELOG / Release notes / Issue #1 / Tool description / health detail) 모두 정합
