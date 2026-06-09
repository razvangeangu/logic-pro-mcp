# 리뷰 가이드 — Issues #10–13 / v3.4.5 작업

> 이 파일이 리뷰 진입점. 작업은 v3.4.5 소스/tag 기준으로 push 완료, current main 테스트 1197 green. stable artifact publication은 notarization secrets 부재로 blocked. GitHub 이슈 #10~#13의 기존 AX deferral 답글은 2026-06-09 후속 구현으로 superseded되며, release 완료 표현은 artifact publication 후에만 사용한다.

---

## 0) 5분 빠른 리뷰

```bash
cd /Users/isaac/projects/logic-pro-mcp

# (1) 무엇을 했는지 — 상태 허브
sed -n '1,80p' docs/tickets/mixer-verification/STATUS.md

# (2) 테스트 green 직접 확인 (~70s)
swift test --no-parallel 2>&1 | tail -3        # → "Test run with 1197 tests passed"

# (3) 변경 규모 한눈에
git diff --stat

# (4) 게시된 답글 확인
gh issue view 10 --repo MongLong0214/logic-pro-mcp --comments | tail -40
```

---

## 1) 산출물 MD (읽는 순서)

| 순서 | 파일 | 내용 |
|---|---|---|
| 1 | `docs/tickets/mixer-verification/STATUS.md` | **허브** — 티켓별 상태/리뷰 이력/최종 상태/남은 일 |
| 2 | `docs/tickets/mixer-verification/VERIFICATION-2026-06-09.md` | 최신 hard verification evidence — deterministic, coverage, targeted live #10-#13 |
| 3 | `docs/tickets/mixer-verification/SPIKE-REPORT.md` | 라이브 Logic 12.2 스파이크 실측 결과 + 2026-06-09 follow-up implementation evidence |
| 4 | `docs/prd/PRD-mixer-verification-honesty.md` | PRD v0.2 (US/AC, §13 Phase2 리뷰 해소, Track 분해) |
| 5 | `docs/tickets/mixer-verification/TICKETS.md` | 티켓별 TDD spec |
| 6 | `docs/tickets/mixer-verification/ISSUE-REPLIES.md` | 이슈 답글 초안/현재 상태 답글 |
| 7 | `CHANGELOG.md` `[3.4.5]` | 릴리스 노트 |
| 8 | `docs/live-verify-v3.4.5.md` | 공개용 live verification 요약 |
| 9 | `docs/releases/v3.4.5.md` | published artifact / SHA / workflow evidence |
| 참고 | `~/.openclaw/workspace/reports/logic-pro-mcp-issues-10-13-prd-2026-06-08.md` | 트랙 A~G 상세 + 8-에이전트 정찰 결론 |

---

## 2) 정밀 리뷰 — 파일 = 티켓 매핑 (변경 의도별로 diff 보기)

각 줄의 `git diff` 명령으로 해당 변경만 보면서 검토하세요.

| 티켓 | 무엇 | diff 명령 | 확인 포인트 |
|---|---|---|---|
| **A1** #10 | MCU_TRACE 트레이스 | `git diff Sources/LogicProMCP/Server/LogicProServer.swift` + 신규 `Sources/LogicProMCP/MIDI/MCUTrace.swift` | TX/RX 2곳 wiring, **stderr 전용**(stdout 불변), env 게이트 |
| **A2/A3** #12/#13 | Scripter HC + select 게이트 | `git diff Sources/LogicProMCP/Channels/ScripterChannel.swift Sources/LogicProMCP/Dispatchers/MixerDispatcher.swift` | 전 경로 HC envelope, value 0~1 fail-closed(**select 前**), verified==true 게이트 |
| **A4** P1-5 | set_pan 정직성 | `git diff Sources/LogicProMCP/Channels/MCUChannel.swift` | `pan_write_mode:"relative_vpot"` (set_pan만, set_volume엔 없음) |
| **B1/B2** #11 | mixer provenance | `git diff Sources/LogicProMCP/Resources/ResourceHandlers.swift Sources/LogicProMCP/State/StateModels.swift` | `data_source` 파생(mixerFetchedAt 기반), `registered` alias 유지(additive) |
| **H1** P1-6 | MIDIEngine restart-safe | `git diff Sources/LogicProMCP/MIDI/MIDIEngine.swift` | stop()이 finish() 안 함, deinit만 finish |
| **H2** P2-5 | AX 좌표 fail-closed | `git diff Sources/LogicProMCP/Accessibility/AXHelpers.swift Sources/LogicProMCP/Accessibility/AXLogicProElements.swift Sources/LogicProMCP/Accessibility/LibraryAccessor.swift Sources/LogicProMCP/Channels/AccessibilityChannel.swift` | 4곳 `point/size(fromRawAttribute:)`로 통일, wrong-subtype→nil |
| **D1** P1-1 | EndToEndTests 정직화 | `git diff Tests/LogicProMCPTests/EndToEndTests.swift` | stale 명령 10개 → isError/구조 assertion (false-green 제거) |
| **D2** P1-4 | live 스크립트 | `git diff Scripts/live-e2e-test.py` | tool-read → resource read 전량 |
| **C2** | 문서 | `git diff docs/API.md docs/TROUBLESHOOTING.md` | channels_exhausted/#10 regression/plugins[]/MCU_TRACE/data_source |
| **F1/F2/F3** #10/#11/#12 | AX mixer readback | `git diff Sources/LogicProMCP/Accessibility/AXLogicProElements.swift Sources/LogicProMCP/Accessibility/AXValueExtractors.swift Sources/LogicProMCP/Channels/AccessibilityChannel.swift Sources/LogicProMCP/Channels/MCUChannel.swift Sources/LogicProMCP/Server/LogicProServer.swift` | Logic 12.2 mixer matcher, fader taper, `verify_source:"ax_readback"`, `plugins_source:"ax"` |
| **G1/G2/G3** #13 | opt-in insert_plugin | `git diff Sources/LogicProMCP/Channels/AccessibilityChannel.swift Sources/LogicProMCP/Dispatchers/MixerDispatcher.swift Sources/LogicProMCP/Channels/ChannelRouter.swift` | L2 confirmation, allowlist, occupied-slot refusal, AX slot readback |
| 신규 테스트 | | `git status --short \| grep Tests` | MCUTrace/MixerProvenance/AXCoordFallback/MixerDispatcherSetPluginParam |

전체 diff를 한 번에:
```bash
git diff                 # 추적 파일
git status --short        # 신규 파일 목록 (?? = 신규)
git diff Sources/LogicProMCP/MIDI/MCUTrace.swift  # 신규는 경로 지정하면 보임 (또는 그냥 파일 열기)
```

---

## 3) 라이브로 직접 재현/검증 (Logic 12.2 떠 있을 때)

현재 release build 기준 targeted E2E에서 확인된 값:
```
# #10 — host write MCU echo가 없어도 AX readback으로 State A
logic_mixer set_volume {track:0, value:0.36}
→ verified:true, verify_source:"ax_readback", observed_ax:0.33777777777777773, observed_mcu:null

# #11 — 그 뒤 resource readback도 AX poll로 갱신
logic://mixer
→ data_source:"ax_poll", strips[0].volume:0.33777777777777773

# #12 — occupied insert slots are named
logic://mixer
→ strips[0].plugins_source:"ax", plugins:[Gain, Gain, Drum Machine Designer]

# #13 — opt-in insert and guardrails
insert_plugin without confirmed:true → confirmation_required
insert_plugin confirmed into empty slot → verified:true, verify_source:"ax_plugin_slot"
insert_plugin confirmed into occupied slot → channels_exhausted / slot_occupied
```
> 새 빌드를 라이브로 돌릴 때 설치 서버가 이미 MCU 포트를 잡고 있으면 `channels_exhausted`가 난다. 기존 `LogicProMCP` 프로세스를 멈추고 `.build/release/LogicProMCP`를 실행해야 한다.

---

## 4) 무엇을 "통과"로 볼지 (수용 기준)
- [ ] `swift test --no-parallel` → 1197 passed (0 fail)
- [ ] `swift build -c release` → passed
- [ ] `swift test --enable-code-coverage --no-parallel` → 1197 passed; coverage hard gate ≥70% region / ≥77% line, with ≥90% line as the tracked target
- [ ] targeted live E2E → #10/#11/#12/#13 issue checks passed
- [ ] git diff가 위 표의 의도와 일치, 범위 외 변경 없음
- [ ] HonestContract 불변식 유지 (State A: reason/error 없음 / B: reason / C: error)
- [ ] GitHub issue #10~#13 status reply posted; release-complete wording is not used before artifact publication; #12/#13 remaining scope is not over-claimed

---

## 5) 보류분 + 다음 단계
1. **Stable artifact publication** — GitHub repo secrets에 notarization credentials를 구성한 뒤 `v3.4.5` release workflow를 rerun한다.
2. **Published SHA256 sync** — GitHub Actions release artifact가 나온 뒤 Formula sha256과 `docs/releases/v3.4.5.md`를 업데이트한다.
3. **Full destructive 200+ live E2E** — 별도 작업. 이번 targeted release gate에는 포함하지 않는다.
4. **#12/#13 future work** — full per-parameter plugin value readback, arbitrary `set_plugin_param insert:N`.

## 되돌리기 (전부 무르고 싶으면)
```bash
git checkout -- .                                   # 추적 파일 변경 취소
git clean -i Sources/ Tests/ docs/                  # 신규 파일 인터랙티브 삭제
# 게시한 답글은 GitHub에서 편집/삭제
```
