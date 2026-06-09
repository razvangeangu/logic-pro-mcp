# PRD: Mixer Write/Read Verification Honesty + 3.4.5 Finalize (Issues #10–13)

**Version**: 0.2
**Author**: MongLong0214 (Isaac) / orchestrated
**Date**: 2026-06-08
**Status**: Approved
**Size**: XL

> v0.2: Phase 2 팀 리뷰(guardian HAS ISSUE P2×4 + boomer PROCEED_WITH_CAUTION) 결과를 §13에 반영 후 승인(자율 전권).

> 근거: GitHub #10/#11/#12/#13 (전부 thomas-doesburg) + 전수 리뷰(`reports/logic-pro-mcp-full-repo-review-2026-06-08.md`) + 8-에이전트 코드 정찰(2026-06-08). 출하 버전: **3.4.5 정식**. insert_plugin = **opt-in 플래그형**. 라이브 스파이크: **가능(Logic 12.2 직접 구동)**.

---

## 1. Problem Statement

### 1.1 Background
정교한 외부 컨트리뷰터(thomas-doesburg)가 `apply_moves`용 **duplicate-and-readback 검증 하니스**를 구축 중. AI 믹싱 결정을 사용자 실제 세션에 적용(write-back)하려면, 모든 쓰기를 복제 프로젝트에서 pre/post 되읽기로 검증해야 함. 네 이슈는 그 하니스의 블로커다. 컨트리뷰터는 #10에서 Isaac이 권한 프로브(timeout bump 1000ms, track-0 first-bank)를 모두 수행하고 **registration/bank/timeout 전부 배제 → "Logic 12.2가 host write 후 fader/V-Pot echo를 안 쏜다"는 real-regression shape를 확정**했으며, 약속된 `MCU_TRACE` 진단을 재요청한 상태(rc12에도 미배포).

### 1.2 Problem Definition
쓰기 결과를 정직하게 되읽을 경로가 **MCU echo 단일 의존**인데 그 echo가 Logic 12.2에서 오지 않는다. 동시에 그 되읽기에 쓸 **AX 코드(`defaultSetMixerValue` write+readback→State A, `defaultGetMixerState`)는 이미 존재하나 라우팅에 안 물려 죽은 코드**이고, 쓰기 경로에 정직성 버그 3종(P1-2/P1-3/P1-5)과 버전·문서 드리프트가 남아 production sign-off를 막는다.

### 1.3 Impact of Not Solving
- 컨트리뷰터(및 LogicProMCP를 감싸는 모든 하니스)가 mixer/plugin write-back을 영구히 비활성 플래그 뒤에 둬야 함 → "AI가 믹싱 결정을 Logic에 반영"의 가장 가치 있는 절반이 막힘.
- 전수 리뷰의 **production-grade contract sign-off 보류** 상태 지속(stale evidence + write 정직성 구멍 + semantics 버그 + 버전 드리프트).

## 2. Goals & Non-Goals

### 2.1 Goals
- [ ] G1: `MCU_TRACE=1` raw-MIDI stderr 트레이스 출하 → 컨트리뷰터가 "host write 후 echo 0개"를 바이트로 확정 (#10 약속 상환).
- [ ] G2: 쓰기 경로 정직성 복구 — `set_plugin_param`/`ScripterChannel`/`set_pan`이 Honest Contract + 멱등성·진실성 계약 준수 (P1-2/P1-3/P1-5).
- [ ] G3: `logic://mixer` 되읽기가 `data_source` provenance + freshness를 정직하게 노출 (#11).
- [ ] G4: T0 라이브 스파이크로 AX 미지수 확정 후, **MCU echo 비의존 라벨링된 독립 volume/pan 되읽기** 추가 → #10/#11 실질 언블락.
- [ ] G5: #12 plugin-param 되읽기(AX 이름 스냅샷) + #13 insert:N/insert_plugin(opt-in 플래그) 정직 범위설정 + 한계 명시.
- [ ] G6: 3.4.5 정식 릴리스 — 버전·문서·테스트 정합 복구(sign-off 4대 보류 폐쇄).
- [ ] G7: **라이브 Logic 12.2 E2E**로 모든 변경의 실동작 검증(unit/integration 외).

### 2.2 Non-Goals
- NG1: Logic Pro 12.2 자체 echo 회귀를 고치는 것(불가능). 의존성 가시화 + 우회 경로만.
- NG2: 기본 production 계약에 무가드 plugin lifecycle 복귀. insert_plugin은 opt-in 플래그 + stock 한정 + 확인 게이트로만.
- NG3: 3rd-party AU 파라미터의 보편적 readback. stock(Channel EQ/Compressor) 한정 best-effort + 한계 명시.
- NG4: AppleScript-direct mixer 되읽기(Logic 스크립팅 딕셔너리에 volume/pan term 없음 — 외부 제약).

## 3. User Stories & Acceptance Criteria

### US-1 (#10): 쓰기 검증 진단 — MCU_TRACE
**As a** 하니스 개발자, **I want** host write 후 Logic이 echo를 쏘는지 raw MIDI로 확인, **so that** echo_timeout이 Logic 회귀인지 우리 버그인지 확정한다.
- [ ] AC-1.1: `MCU_TRACE=1` 환경에서만 `ProductionMCUTransport` TX/RX가 `MCU TX/RX: <hex>`를 **stderr**로 출력(stdout=JSON-RPC 불변).
- [ ] AC-1.2: 25ms 폴 cadence에서도 누락 없이 출력(rate-limiter 우회, `FileHandle.standardError` 직접).
- [ ] AC-1.3: 미설정 시 출력 0, envelope/동작 변화 0.
- [ ] AC-1.4: **라이브 E2E**: `MCU_TRACE=1`로 set_volume track:0 1회 실행 → 캡처된 트레이스에 host pitch-bend는 보이고 **inbound echo 프레임 수를 카운트**(0이면 #10 회귀 확정).

### US-2 (#12/#13 write-half / P1-3): set_plugin_param 정직성
**As a** 하니스, **I want** plugin-param write가 Honest Contract envelope + 정확한 적용값을 반환, **so that** silent coercion 없이 결과를 신뢰한다.
- [ ] AC-2.1: `ScripterChannel.execute`가 HC State B(`readback_unavailable`) envelope 반환(extras: operation/method:"scripter"/insert/param/cc/midi_value/requested_value/clamped).
- [ ] AC-2.2: `value` 0.0…1.0 범위 밖이면 State C `invalid_params`(fail-closed, set_volume과 동일) — silent clamp 제거.
- [ ] AC-2.3: 기존 plaintext를 string-match하던 내부 호출자 0 확인.

### US-3 (P1-2): set_plugin_param target-faithful
**As a** 사용자, **I want** 선택이 불확실하면 plugin write를 거부, **so that** 엉뚱한 트랙에 silently 쓰지 않는다.
- [ ] AC-3.1: pre-write `track.select`가 State B(verified:false)면 State C로 hard-fail(에러에 원본 select_response 포함).
- [ ] AC-3.2: verified select는 기존대로 진행.

### US-4 (P1-5): set_pan 멱등·정직
**As a** 하니스, **I want** set_pan이 상대 회전임을 정직하게 노출하고 no-op delta는 안 움직이게, **so that** 반복 호출 드리프트를 안다.
- [ ] AC-4.1: speed가 0으로 매핑되는 delta는 전송하지 않음(no-op).
- [ ] AC-4.2: envelope에 `pan_write_mode:"relative_vpot"` extra로 상대 nudge임을 명시.
- [ ] AC-4.3: (T2) 스파이크가 허용하면 set_pan을 AX 절대 쓰기로 전환해 멱등 달성.

### US-5 (#11): mixer 되읽기 provenance
**As a** 하니스, **I want** `logic://mixer` 값의 출처/신선도를 wire에서 판단, **so that** 되읽기를 신뢰할지 결정한다.
- [ ] AC-5.1: 최상위 `data_source` 필드(`ax_poll`/`mcu_echo`/`cache_stale`/`mixer_not_visible`) — mixerFetchedAt age + mcu_connected에서 파생(하드코딩 금지).
- [ ] AC-5.2: 쓰기측과 정합: `mcu_registered` + `mcu_last_feedback_age_ms` 추가(`registered`는 1릴리스 alias).
- [ ] AC-5.3: `mcu_connected:false`면 strips는 stale-by-definition 힌트 명시.
- [ ] AC-5.4: `logic://mixer/{strip}`도 동일 envelope+data_source.

### US-6 (#10/#11, T2): MCU echo 비의존 AX 독립 되읽기
**As a** 하니스, **I want** MCU echo가 안 와도 AX로 fader/pan을 되읽어 검증, **so that** Logic 12.2에서도 write-back을 켤 수 있다.
- [ ] AC-6.1: `findFader`/`findPanKnob`을 AXDescription 매칭으로 하드닝 + `extractSliderRange`로 0..1 정규화(스파이크 결과 반영).
- [ ] AC-6.2: MCU State B echo_timeout 시 AX 후속 read → `observed_ax` + `data_source:"ax"`를 envelope extras에 부착. MCU cache(channelStrips) 절대 미오염.
- [ ] AC-6.3: Mixer 비가시/occluded 시 fail-closed `data_source:"mixer_not_visible"`(mislabel 금지).
- [ ] AC-6.4: **라이브 E2E**: set_volume → AX 되읽기 observed가 requested와 tolerance 내 일치(State A) 실증.

### US-7 (#12, T2): plugin-param 되읽기(AX 이름 스냅샷)
**As a** 하니스, **I want** insert 체인 이름/bypass를 되읽어 index map 구축, **so that** EQ/comp write를 검증 가능 인덱스로 매핑한다.
- [ ] AC-7.1: `ChannelStripState.plugins`를 AX insert-슬롯 스캔으로 채움(`{index,name,isBypassed}`), `data_source:"ax"`, MCU cache와 분리, throttle/opt-in.
- [ ] AC-7.2: full param 값 readback 한계(blind Scripter index↔AX slider 비1:1)를 #12에 정직 명시.

### US-8 (#13, T3): opt-in 플래그형 insert_plugin + insert:N
**As a** build-mode 사용자, **I want** 명시적 opt-in으로 stock 유틸을 삽입/지정 insert에 param write, **so that** gain-staging relocation을 자동화한다.
- [ ] AC-8.1: insert_plugin은 기본 비활성. `--approve-channel`/build-mode 플래그 + stock allowlist(Gain/Channel EQ/Compressor/Noise Gate) 뒤에서만.
- [ ] AC-8.2: DestructivePolicy plugin-insert L2 엔트리 + confirmation_required.
- [ ] AC-8.3: AX 메뉴 삽입 후 슬롯 AXValue==요청 이름 검증, 불일치 시 fail-closed.
- [ ] AC-8.4: insert:N은 Scripter CC 미주소지정 → AX 플러그인창 포커스 + AX param 구동(스파이크 게이트).

### US-9 (G6): 3.4.5 정식 정합
**As a** 운영자, **I want** 버전·문서·테스트가 단일 진실을 말하게, **so that** 외부 production sign-off가 가능하다.
- [ ] AC-9.1: 7개 면(ServerConfig/manifest x2/Formula+sha256/install.sh/README/CHANGELOG/ResourceProvider) `3.4.5`로 lockstep + 배너 테스트 3곳.
- [ ] AC-9.2: TROUBLESHOOTING 레거시 `All channels exhausted` → `channels_exhausted`; #10 regression 행; plugins[] 빈상태/MCU_TRACE/data_source 문서화.
- [ ] AC-9.3: EndToEndTests + live-e2e-test.py stale surface 제거 → 현재 public surface + 구조 assertion.

## 4. Technical Design

### 4.1 Architecture Overview
변경 없는 축: `8 dispatchers → ChannelRouter → 7 channels`, `ResourceHandlers → StateCache → StatePoller`, `HonestContract A/B/C`. 본 작업은 (a) MCU 쓰기 검증 레일에 **AX 독립 검증 훅** 추가(cache 미오염, 라벨링), (b) `logic://mixer` envelope provenance 강화, (c) Scripter write를 HC로 통일, (d) opt-in AX insert 경로 신설.

### 4.2 Data Model Changes
- `ChannelStripState.plugins`(이미 선언, 미채움)를 AX 스캔으로 채움. 필요 시 `PluginSlotState`에 param-readback 필드 검토(T2).
- Codable 하위호환: 기존 필드 default 유지, 신규는 `decodeIfPresent`.

### 4.3 API Design (MCP wire — additive, HC 불변식 유지)
| Surface | 변경 | 비고 |
|--------|------|------|
| `logic://mixer` | +`data_source`, +`mcu_registered`, +`mcu_last_feedback_age_ms`; `registered` alias 1릴리스 | additive; ResourceSchemaTests 갱신 |
| `logic://mixer/{strip}` | envelope+data_source 부여 | 기존 bare → envelope |
| set_volume/set_pan State A/B | +`observed_ax`(T2), +`data_source`; set_pan +`pan_write_mode` | extras로 additive |
| set_plugin_param | plaintext → HC State B(readback_unavailable) + extras | wire shape 정직화 |
| insert_plugin (opt-in) | flagged 재노출, stock 한정, 검증 포함 | 기본 비활성 |

HC 불변식: State A는 reason/error 금지, State B는 reason 필수·error 금지, State C는 error 필수·verified/reason 금지. 신규는 전부 extras.

### 4.4 Key Technical Decisions
| Decision | Options | Chosen | Rationale |
|----------|---------|--------|-----------|
| #10/#11 검증 소스 | (a)State B 유지 (b)AX 독립 라벨 되읽기 (c)AppleScript | **(b)** | AS는 mixer term 없음; AX write+readback 코드 이미 존재; data_source로 정직 라벨 → MCU cache 미오염 |
| #12 readback | (1)Scripter echo (2)AX plugins[] 스냅샷 | **(2)** | (1)은 send-only transport라 구조적 불가; (2)는 PluginInspector 스캐폴드 활용 |
| #13 insert | (A)읽기전용 (B)opt-in 플래그 (C)보류 | **(B)** | gain-staging 유스케이스 살리며 rc 제거 사유+Level2 위험 동시 존중 |
| set_pan 멱등 | 상대 유지 / AX 절대 | **AX 절대(T2)** + 상대 정직 노출(T1) | MCU V-Pot은 절대 명령 없음(프로토콜 한계) |
| 버전 | rc13 / 3.4.5 정식 / 3.5.0 | **3.4.5 정식** | rc 사이클 종료; sign-off 보류 동시 폐쇄 |

### 4.5 Codex / 리뷰 표준
- 모든 boomer/codex 실행: **`codex exec -m gpt-5.5 -c 'model_reasoning_effort="xhigh"'`** (사용자 지시 + 메모리 규칙; orchestration.md의 5.3 무효화).

## 5. Edge Cases & Error Handling
| # | Scenario | Expected | Severity |
|---|----------|----------|----------|
| E1 | Mixer 패널 닫힘 → AX read 불가 | `data_source:"mixer_not_visible"` fail-closed, verified 미승격 | High |
| E2 | AXSlider 스케일이 dB | extractSliderRange로 0..1 정규화, 불가 시 deferred | High |
| E3 | findFader 위치 오타깃(sends 슬라이더) | AXDescription 매칭, 실패 시 element_not_found | High |
| E4 | set_pan delta==0 | no-op(미전송) | Med |
| E5 | set_plugin_param value 범위 밖 | State C invalid_params | Med |
| E6 | track.select State B 후 plugin write | State C hard-fail | High |
| E7 | insert_plugin stock allowlist 밖 이름 | 거부(State C), 삽입 안 함 | High |
| E8 | insert 후 슬롯 이름 불일치 | fail-closed, 롤백/보고 | High |
| E9 | 버전 bump 시 배너 테스트 미갱신 | CI red(의도된 가드) | Med |

## 6. Security & Permissions
### 6.1/6.2 Authorization
- insert_plugin = signal-chain mutation → **DestructivePolicy L2 + confirmation_required + opt-in 플래그**. 기본 production 경로 제외.
- AX 쓰기/읽기: Accessibility + Automation 권한 필요(이미 granted). Mixer 가시성 게이트.
### 6.3 Data Protection
- 라이브 E2E는 **복제/스크래치 프로젝트**에서만. 사용자 실제 세션 무변경(컨트리뷰터 하니스 패턴 준수).

## 7. Performance & Monitoring
| Metric | Target | 측정 |
|--------|--------|------|
| AX 되읽기 추가 지연(set_volume) | < 600ms(echo timeout window 내 후속) | E2E 계측 |
| plugins[] AX 스캔 | throttle, 3s 폴 cadence 비차단 | StatePoller 계측 |
- 로깅: MCU_TRACE는 stderr 전용, 기본 off. `data_source`로 운영자 신뢰도 판단.

## 8. Testing Strategy
### 8.1 Unit (Swift Testing, `swift test --no-parallel`)
- HC envelope(A/B/C 불변식), MCU_TRACE 게이트, Scripter HC wrap + range, select State-B 게이트, set_pan no-op/relative extra, logic://mixer data_source 라벨, AX findFader/range 정규화.
### 8.2 Integration
- ChannelRouter 경로, ResourceHandlers envelope, StatePoller plugins 스캔(fake AX tree).
### 8.3 Edge Case Tests
- Section 5 E1-E9 전수.
### 8.4 라이브 E2E (Logic 12.2 직접 구동) — **이 PRD의 필수 게이트**
- T0 스파이크(§아래) + 각 기능 실동작: set_volume/pan AX 검증, set_plugin_param 정직 envelope, plugins[] 스냅샷, (opt-in) insert_plugin gain-staging 시나리오.
- 빌드 3종: `swift build -c release` + `swift test --no-parallel`(+`--enable-code-coverage`, region≥65/line≥72) + 라이브 E2E PASS.

### 8.5 T0 라이브 스파이크 프로토콜 (T2/T3 게이트)
복제 프로젝트 + `MCU_TRACE=1`:
1. **Echo 유무(#10)**: set_volume track:0 → 트레이스의 inbound pitch-bend 프레임 수. set_pan → CC 0x30..0x37 수.
2. **Fader/Pan AXSlider**: AXRole/AXValue/AXMin/AXMax/AXDescription/AXIdentifier 덤프; 스케일(dB vs 0-1) + getMixerArea identifier 매칭 + 슬라이더 순서.
3. **Plugin window param(#12)**: stock EQ/Comp 창 AXSlider/AXValue 덤프; 값/이름 읽힘+안정성.
4. **Insert 슬롯(#12/#13)**: 빈 vs 채움 슬롯 AX role/value.
→ 산출: 스파이크 리포트 → 각 T2/T3 sub-item go/no-go. 실패 항목은 "정직한 deferred"로 이슈 명시.

## 9. Rollout Plan
### 9.1 Migration
- DB 없음. wire 변경은 additive(registered alias). 마이그레이션 불필요.
### 9.2 Feature Flag
- insert_plugin/insert:N: opt-in 플래그(기본 off). AX 검증 되읽기: data_source 라벨로 점진 신뢰.
### 9.3 Rollback
- git revert 단위 = 트랙별 티켓. 버전 finalize는 별도 커밋. 문제 시 트랙 단위 revert + 빌드 3종 재확인.

## 10. Dependencies & Risks
### 10.1 Dependencies
| Dependency | Owner | Status | Risk |
|-----------|-------|--------|------|
| Logic 12.2 라이브 세션 | Isaac | **Ready(연결됨)** | 세션 종료 시 스파이크/E2E 지연 |
| Codex CLI gpt-5.5 xhigh | boomer | 필요 | 실행 불가 시 Isaac 에스컬레이션 |
| 스파이크 결과 | T0 | Phase 5 | AX 미지수 확정 전 T2 착수 불가 |

### 10.2 Risks
| Risk | P | Impact | Mitigation |
|------|---|--------|------------|
| AX 스케일 미상 | M | 오정규화→오검증 | 스파이크 후만 구현; extractSliderRange |
| 위치기반 슬라이더 오타깃 | M | 잘못된 pan/sends | AXDescription 매칭 선행 |
| Mixer 비가시 | M | 되읽기 공백 | fail-closed 라벨 |
| wire 변경 하니스 파손 | L | strict-schema 깨짐 | additive+alias+문서 고지 |
| insert_plugin 안티패턴 재발 | M | "거짓말 descriptor" | 검증경로 없는 노출 금지; L2 게이트 |
| 배너 테스트 정확매치 | M | CI red | C1 AC에 3곳 명시 |
| Formula rc7 자산 404 | L | 인스톨 실패 | 자산 존속 확인 |

## 11. Success Metrics
| Metric | Baseline | Target | 측정 |
|--------|----------|--------|------|
| #10/#11 write-back 검증 가능 | 0(불가) | volume State A 실증 | 라이브 E2E |
| 정직성 버그(P1-2/3/5) | 3 | 0 | 테스트 |
| 버전 면 정합 | rc7≠HEAD | 3.4.5 단일 | VersionConsistency 확장 |
| sign-off 보류 사유 | 4 | 0 | 전수 리뷰 재판정 |

## 12. Open Questions
- [ ] OQ-1: 릴리스 타이밍 — T1만 먼저 3.4.5 vs T2까지 묶어 한 번에? (Phase 5 진입 시 결정)
- [ ] OQ-2: `registered`→`mcu_registered` alias 1릴리스 vs 즉시 전환?
- [ ] OQ-3: 답글 타이밍 — T1 출하 직후 vs 3.4.5 정식 후 일괄?
- [ ] OQ-4: 스파이크에서 AX 검증 신뢰도 충분 시 set_volume verified:true 자동 승격 vs opt-in?

## 13. Phase 2 Review Resolutions (v0.2)

> guardian VERDICT: HAS ISSUE (P0/P1=0, P2=4). boomer(codex gpt-5.5 xhigh, 192K): PROCEED_WITH_CAUTION. 아래로 전부 해소 후 Approved.

- **R1 [AX-verifier invocation / boomer#1]**: 라우터 first-success가 State B(success)에서 단락 → AX verifier를 `.accessibility` 폴백으로 append 불가. **결정: AX 검증은 MCUChannel에 read-only AX closure를 주입**해 echo timeout 직후 호출(라우팅 테이블 변경 X). `observed_ax`/`verify_source:"ax_readback"`를 MCUChannel이 envelope extras에 직접 부착. (§4.1/4.4)
- **R2 [insert 롤백 / guardian]**: **AC-8.5 신설** — 삽입 후 슬롯 이름 ≠ 요청 시 삽입 슬롯 제거(undo) + 체인 원복 검증 + State C 보고. AC-8.3↔E8 문구 일치.
- **R3 [엣지 3종 / guardian]**: **E10** AX 권한 작업중 취소 → fail-closed. **E11** 동시 write / poll-중-write → 직렬화 또는 거부. **E12** late-echo stale — echo timeout 후 도착 프레임이 이후 write/observed에 오매칭 안 되도록 sendAt/write-id 페어링 가드(기존 `requireFreshAfter` 확장). AC-6.2 역방향(late echo가 fresh AX observed 덮어쓰기) 금지 명시.
- **R4 [cache-isolation 테스트 / guardian]**: §8.1에 "AX observed read 후 `cache.channelStrips` 불변" 단정 단위테스트 추가(AC-6.2 핀).
- **R5 [allowlist 로케일 / 점유슬롯 / guardian]**: AC-8.1 allowlist를 **로케일 독립 식별자(AU component/subtype)로 매칭**(영문 이름 매칭 금지 — 13 locale). insert:N 점유 슬롯 = **거부**(displacement 금지).
- **R6 [data_source enum 통일]**: canonical — read: `mcu_echo|ax_poll|ax|cache_stale|mixer_not_visible`; write-verify: `verify_source: mcu_echo|ax_readback|none`. (§4.3)
- **R7 [sign-off 잔여 / boomer#7]**: P1-6(MIDIEngine restart-unsafe) + P2-5(AX coord fallback subtype 미검증)도 전수리뷰 sign-off 보류 포함. **Track H 신설(release-integrity, Level 1)**: H1 MIDIEngine `start→stop→start` inbound stream 재생성 + 회귀테스트, H2 AX coord fallback call-site `AXValueGetValue` Bool 검사 통일. 3.4.5 정식이 sign-off를 정직히 닫으려면 포함.
- **R8 [set_pan AC-4.1 재정의 / guardian·strategist]**: encodeVPot `speed=max(1,..)` 바닥 1이라 입력으로 speed 0 불가 → "delta==0 no-op" 무효. **재정의**: T1은 envelope에 `pan_write_mode:"relative_vpot"` + `observed:null` 정직 노출 + set_pan이 절대-target 계약이 아님을 reason/문서 명시. **멱등 절대 pan은 T2(F2) AX 절대쓰기로만**. T1에서 no-op 주장 안 함.
- **R9 [E2E 실세션 보호 / guardian]**: §6.3 — 라이브 E2E 전 프로젝트명 suffix/복제 확인 운영 가드 + 로그.
- **R10 [E2E 매트릭스 / boomer#12]**: §8.4 확장 — mixer hidden/occluded · AX 권한 revoke · locale(KO/EN) · track 0/7/8/banked · pan −1/0/+1 · MCP stop/start · approval revoke · failed-insert no-residue · **MCU_TRACE 켠 상태 stdout JSON-RPC purity** · write 후 resource provenance.
- **R11 [정확성 / boomer]**: `defaultGet/SetMixerValue` 클로저는 `AccessibilityChannel.swift:168-170`에 등록됨(미호출). 구현 시 "순수 dead code" 가정 금지, 라우팅 도달 재확인.

### Track H — Release Integrity (신설, T1)
- **H1 (P1-6)**: `MIDIEngine` `stop()` 후 `start()`가 inbound `AsyncStream`/continuation을 재생성하도록 수정 + `start→stop→start→deliverInbound` 회귀테스트.
- **H2 (P2-5)**: `AccessibilityChannel.postMouseClickAt`/`trackViewport`, `AXLogicProElements` track-header coord-click, `LibraryAccessor` header click의 좌표 fallback을 `AXHelpers.getPosition/getSize` 패턴으로 통일(`AXValueGetValue` Bool 검사) + wrong-subtype 회귀테스트.

### Adopted (concurrent session, 2026-06-08, verified 1146 green)
- **A2 완료**: `ScripterChannel` 전 경로 HC envelope(State C notImplemented/invalidParams/portUnavailable; 성공 State B readback_unavailable + extras) + value 0.0…1.0 fail-closed. **A3 완료**: `MixerDispatcher.set_plugin_param` `verified==true` State-B select 게이트 + `MixerDispatcherSetPluginParamTests`. 보너스: `InstallScriptContractTests` macos-13→14 latent fix.

---
<!-- 트랙 분해(A~G) 상세는 외부 기획 노트(~/.openclaw/workspace/reports/logic-pro-mcp-issues-10-13-prd-2026-06-08.md, 비-repo) §4 참조. 본 문서가 canonical PRD. insert_plugin(#13)은 US-8 + §13(R2/R5) 참조. v0.2 §13에 Phase 2 해소 + Track H + 채택분 기록. -->
