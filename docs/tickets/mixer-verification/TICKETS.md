# Tickets: mixer-verification-honesty (Issues #10–13, v3.4.5)

> PRD: `docs/prd/PRD-mixer-verification-honesty.md` (v0.2 Approved). TDD 강제: Red→Green→Refactor.
> 테스트 러너: `swift test --no-parallel`. Baseline: 1146 green (A2/A3 채택분 포함).

## 범례
- Tier T1=결정론적(지금) · T2=스파이크 후 · T3=에스컬레이션/opt-in.
- 상태: Todo / In Progress / Done / Adopted / Deferred(spike).

---

## ✅ T-A2 (Adopted) — ScripterChannel Honest Contract + range guard  [#12/#13, P1-3]
PRD US-2. **Adopted** (concurrent session, verified). 전 경로 HC envelope, 0..1 fail-closed. 1146 green.

## ✅ T-A3 (Adopted) — set_plugin_param State-B select gate  [P1-2]
PRD US-3. **Adopted**. `verified==true` 아니면 State C(원본 select_response 포함). `VerifiedSelectMockChannel` 공유.

---

## T-A1 — MCU_TRACE raw-MIDI stderr trace  [#10, T1]
- **PRD**: US-1. **Priority**: P1. **Size**: S. **Depends**: None.
- **Objective**: `MCU_TRACE=1`일 때 ProductionMCUTransport TX/RX를 stderr hex 덤프(stdout 불변, rate-limiter 우회).
- **AC**: AC-1.1~1.3 (라이브 AC-1.4는 E1 스파이크).
- **TDD (Red)**:
  | # | Test | Type | Expected |
  |---|------|------|----------|
  | 1 | `testMCUTraceEnvGateOffNoOutput` | Unit | env 미설정 시 trace 함수가 출력 0 (capture) |
  | 2 | `testMCUTraceEnvGateOnHexFormat` | Unit | `MCU_TRACE=1`일 때 `formatMCUTrace(dir:.tx, bytes:[0xE0,..])` == `"MCU TX: e0 .."` |
  | 3 | `testMCUTraceWritesStderrNotStdout` | Unit | trace 경로가 stdout에 안 씀(FileHandle.standardError 사용 단정) |
- **Files**: `Server/LogicProServer.swift`(TX:444-450, RX:464-473), `Utilities/Logger.swift`(hex helper, optional 별도 `MCUTrace` util로 테스트 용이화). 신규 test `MCUTraceTests.swift`.
- **Impl**: env 게이트 helper(MCUChannel.echoTimeoutMs 패턴) + `FileHandle.standardError.write` 직접(rate-limiter 우회). 순수 포맷 함수 분리해 단위테스트.
- **Edge**: stdout JSON-RPC purity(E2E R10).

## T-A4 — set_pan honest relative disclosure  [P1-5, T1]
- **PRD**: US-4 (R8 재정의). **Priority**: P2. **Size**: S. **Depends**: None.
- **Objective**: set_pan이 절대 target이 아닌 상대 V-Pot nudge임을 envelope에 정직 노출. (멱등 절대 pan은 F2.)
- **AC**: envelope에 `pan_write_mode:"relative_vpot"` extra; `observed`는 echo 없으면 null; no-op 주장 제거.
- **TDD (Red)**:
  | 1 | `testSetPanCarriesRelativeModeExtra` | Unit | State A/B 모두 `pan_write_mode=="relative_vpot"` |
  | 2 | `testSetPanDoesNotClaimAbsoluteIdempotence` | Unit | 동일 pan 2회 → 둘 다 동일 envelope shape, verified 함부로 true 아님 |
- **Files**: `Channels/MCUChannel.swift:333-370`, `MCUChannelTests`/`MCUMixerWriteDiagnosticsTests`.
- **Note**: encodeVPot speed 바닥 1 → speed 0 no-op 불가(R8). 상대성만 정직 노출.

## T-B1 — logic://mixer envelope provenance  [#11, T1]
- **PRD**: US-5. **Priority**: P1. **Size**: M. **Depends**: None.
- **Objective**: `data_source` + triplet 정합 + staleness 힌트.
- **AC**: AC-5.1(data_source: mcu_echo|ax_poll|cache_stale, mixerFetchedAt age+mcu_connected 파생) · AC-5.2(`mcu_registered`+`mcu_last_feedback_age_ms` 추가, `registered` 1릴리스 alias) · AC-5.3(mcu_connected:false → stale 힌트).
- **TDD (Red)**:
  | 1 | `testMixerEnvelopeHasDataSource` | Unit | fresh mixerFetchedAt → `data_source=="ax_poll"` |
  | 2 | `testMixerEnvelopeStaleWhenMcuDisconnectedAndOld` | Unit | mcu_connected:false + old age → `data_source=="cache_stale"` + stale 힌트 |
  | 3 | `testMixerEnvelopeKeepsRegisteredAlias` | Unit | `registered`(alias)와 `mcu_registered` 둘 다 present |
  | 4 | `testMixerEnvelopeAdditiveSchema` | Unit | 기존 ResourceSchemaTests 키 유지(additive) |
- **Files**: `Resources/ResourceHandlers.swift:270-285`, `MCUChannel.mcuConnectionExtras` 재사용, `ResourceSchemaTests.swift`.

## T-B2 — logic://mixer/{strip} envelope parity  [#11, T1]
- **PRD**: US-5 AC-5.4. **Priority**: P2. **Size**: S. **Depends**: T-B1.
- **AC**: readMixerStrip가 cache_age_sec/fetched_at/data_source 부여(bare → envelope).
- **TDD**: `testMixerStripHasEnvelope` (Unit). **Files**: `ResourceHandlers.swift:432-440`.

## T-C1 — version finalize 3.4.5 (7면 sync)  [G6, T1, **L2**]
- **PRD**: US-9 AC-9.1. **Priority**: P1. **Size**: M. **Depends**: 전 코드 트랙 완료 후 마지막.
- **AC**: ServerConfig/manifest(x2)/Formula(+sha256)/install.sh/README/CHANGELOG(rc8-12 통합+본작업)/ResourceProvider.versionReleaseTimestamp/배너 테스트 3곳 → `3.4.5` lockstep.
- **TDD**: `VersionConsistencyTests` 통과 + 배너 `LogicProServerTransportTests:386/391/410` 갱신. rc7 자산 존속 확인.
- **Files**: 위 7면 + `LogicProServerTransportTests.swift`. **Gate**: Level 2(릴리스) — Isaac 승인.

## T-C2 — docs accuracy  [G6, T1]
- **PRD**: US-9 AC-9.2. **Priority**: P2. **Size**: M.
- **AC**: TROUBLESHOOTING `All channels exhausted`→`channels_exhausted`; #10 regression 행; plugins[] 빈상태/MCU_TRACE/data_source/set_plugin_param HC 문서화; API.md set_plugin_param envelope.
- **Files**: `docs/{TROUBLESHOOTING,HONEST-CONTRACT,API,SETUP}.md`. (스타일/텍스트 → snapshot/visual 검증으로 TDD 대체 가능.)

## T-D1 — EndToEndTests stale surface 제거  [P1-1, T1]
- **PRD**: US-9 AC-9.3. **Priority**: P1. **Size**: M.
- **AC**: stale command(`logic_mixer.get_state` 등) + `!isEmpty`-only → 현재 public surface + 구조/필드/asserted-error-shape. 제거 read는 resource read 테스트로 대체.
- **TDD**: 갱신된 EndToEndTests가 의도적 stale fixture에 red, 현재 surface에 green.
- **Files**: `Tests/.../EndToEndTests.swift`.

## T-D2 — live-e2e-test.py stale surface 제거  [P1-4, T1]
- **PRD**: US-9 AC-9.3. **Priority**: P2. **Size**: M.
- **AC**: tool-read 구형 호출 → `resources/read`; envelope/schema-field assertion. dry-run snapshot diff.
- **Files**: `Scripts/live-e2e-test.py`.

## T-H1 — MIDIEngine restart-safe inbound stream  [P2-5 보류→P1-6, T1]
- **PRD**: §13 R7 / Track H. **Priority**: P1. **Size**: M. **Depends**: None.
- **Objective**: `stop()` 후 `start()`가 inbound `AsyncStream`/continuation 재생성 → restart-safe.
- **TDD (Red)**: `testMIDIEngineRestartDeliversInbound` — `start→stop→start→deliverInbound` 후 consumer가 이벤트 수신(현재는 못 받음 → red).
- **Files**: `MIDI/MIDIEngine.swift:init/start/stop`, `MIDIEngineTests.swift`.
- **Edge**: finish()를 terminal teardown으로 제한.

## T-H2 — AX coord fallback subtype hardening  [P2-5, T1]
- **PRD**: §13 R7 / Track H. **Priority**: P2. **Size**: M. **Depends**: None.
- **Objective**: coord-click fallback call-site들을 `AXHelpers.getPosition/getSize`(AXValueGetValue Bool 검사)로 통일.
- **AC**: wrong-subtype AXValue 주입 시 misclick 대신 clean fail(nil/false).
- **TDD (Red)**: `testCoordFallbackRejectsWrongSubtype` — 각 call-site에 wrong-subtype 주입 → (0,0) 클릭 안 함.
- **Files**: `AccessibilityChannel.swift`(postMouseClickAt/trackViewport), `AXLogicProElements.swift`(track-header), `LibraryAccessor.swift`(header click).

---

## T-E1 — T0 라이브 스파이크 (게이트)  [T2/T3 gate, 라이브 Logic]
- **PRD**: §8.5. **Depends**: T-A1. **Output**: 스파이크 리포트 → T-F*/T-G* go/no-go.
- 1. echo 유무(MCU_TRACE) 2. fader/pan AXSlider 스케일·식별자·AXDescription 3. stock EQ/Comp param AX 4. insert 슬롯 AX role/value.

## T-F1/F2/F3 — AX 독립 되읽기 (T2, 스파이크 후 상세화)
- F1 AX 타깃 하드닝(AXDescription+extractSliderRange 정규화). F2 MCUChannel 내부 AX read closure 주입 → echo timeout 후 `observed_ax`+`verify_source:"ax_readback"`(R1), cache 미오염(R4 테스트). F3 plugins[] 이름 스냅샷(R5 로케일 독립). AC/TDD는 스파이크 결과로 확정.

## T-G1/G2/G3 — opt-in insert_plugin (T3, L2, 스파이크 후)
- G1 opt-in 플래그+stock allowlist(로케일독립)+DestructivePolicy L2 confirmation+삽입후 이름검증 fail-closed+**AC-8.5 rollback/undo**(R2). G2 insert:N via AX 플러그인창 포커스(점유슬롯 거부 R5). G3 param 값 readback 한계 명시. AC/TDD는 스파이크 결과로 확정. **Isaac Level 2 개별 승인.**
