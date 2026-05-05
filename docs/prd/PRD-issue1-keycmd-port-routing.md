# PRD: Issue #1 — MIDIKeyCommands port routing + channel encoding + setup honesty

**Version**: 0.4
**Author**: Isaac (orchestrated via Claude Opus 4.7)
**Date**: 2026-05-04
**Status**: Approved (Loop 3 의견 분기 — strategist ALL PASS, guardian/boomer P1 잔존; Rules §8 3회 한도로 micro-revision v0.4 후 Phase 3 진입; v0.4가 4건 P1 모두 fact 정정으로 해소)
**Size**: L
**GitHub Issue**: https://github.com/MongLong0214/logic-pro-mcp/issues/1
**Reporter**: xaexx1
**Target Release**: v3.1.6 (v3.1.5는 Issue #3/#4/#5 thomas-doesburg AppleScript read-path resilience로 점유. Issue #1의 BREAKING channel encoding 변경은 별도 release로 communication clarity 확보 — Phase 4 Loop 1 결정)
**Workflow**: C (Level 2 동기 승인 — BREAKING change 포함)

**Revision history**:
- v0.1 (2026-05-04 초안): Phase 2 Loop 1 리뷰에서 P1×4, P2×5 발견 (HAS ISSUE)
- v0.2 (2026-05-04 revision): routing 설계 dispatcher-level direct로 교체, scope 확장(play_sequence/record_sequence/pitch_bend/aftertouch), "all covered" → audited matrix, ScripterChannel 제외, Scripts/install.sh 포함. Loop 2 리뷰에서 P1×4 발견 (KeyCmd readiness gate / matrix 정확도 / record_sequence 위치 / NoteSequenceParser API)
- v0.3 (2026-05-04 revision): KeyCmd readiness bypass policy (router-level allowlist), AC-3.4 matrix 사실 정정 (transport.play/stop 행 삭제, view 행 통일, note.up_*/down_* orphan 처리), record_sequence scope 분리 (NG7), NoteSequenceParser API 변경 명시, validateMidiChannel float reject 패턴, NG8 (mmc_*/sysex/step_input port 비지원). Loop 3 리뷰: strategist ALL PASS w/ P3 cosmetic, guardian HAS ISSUE w/ P1 matrix accuracy, boomer ESCALATE w/ P1×4. Rules §8 (3회 한도)로 추가 loop 금지 — micro-revision으로 진행.
- v0.4 (2026-05-04 micro-revision): AC-3.4 matrix NavigateDispatcher 사실 정정 (smart_controls/plugin_windows orphan으로, automation.toggle_view=logic_navigate 노출 명시, automation.set_mode primary MCU 정정, capture_recording cgEvent 미매핑 명시), §4.3 record_sequence 스타일 comment 정정, §8.1 test 이름 + 카운트 정정 (8→7 ops, 16→14 cases, IgnoresWithWarning→RejectsPort), AC-2.6 notes ch field BREAKING 표 추가 (Boomer P1-3), §4.1 router-gate available==false 분기에서 portUnavailable HC envelope 직접 반환 명시 (Boomer P1-2), AC-5.1 automation.toggle_view "always-required" 제거 (cgEvent fallback 존재), §4.1 readiness rationale chicken-and-egg framing.

---

## 1. Problem Statement

### 1.1 Background
v3.1.1 사용자(`xaexx1`)가 Logic Pro 12.2 + macOS 26.5 환경에서 `MIDIKeyCommands` 채널이 작동하지 않는다고 GitHub Issue #1로 P1급 정확한 진단 보고. v3.1.2~v3.1.4에서 HC envelope wrap, 라이브 race fix, AX occlusion 등은 처리했으나 본 이슈의 root cause인 **port routing 자체와 docs misleading**은 그대로.

보고자가 핵심 분석을 정확히 수행:
- Logic 12.2 Key Commands 패널이 `.plist` import를 거부 (`.logikcs` schema만 허용)
- `logic_midi.send_cc`가 `LogicProMCP-MIDI-Internal` 포트로만 송신 → 사용자가 Logic Controller Assignments → Learn Mode로 수동 바인딩 시도 시 `MIDIKeyCommands` 채널의 실제 송신 포트(`LogicProMCP-KeyCmd-Internal`)와 불일치 → 바인딩 매칭 실패
- `channel: 16` 입력했는데 Logic이 Ch 1로 캡처 (코드 분석: `midiChannel(0...16)` 허용 + wire mask `0x0F` → `16 & 0x0F = 0` → off-by-one)
- Homebrew formula `depends_on xcode: ["15.0", :build]`가 CLT-only host 차단 (보고자가 수동 binary install로 우회)

### 1.2 Problem Definition (v0.2 보강)

1. **Port routing 결함**: `logic_midi.send_*` **6종**(send_cc / send_note / send_chord / send_program_change / send_pitch_bend / send_aftertouch) + `play_sequence` + `record_sequence` 모두 항상 `MIDI-Internal` 포트만 사용 → MIDIKeyCommands 채널의 manual MIDI Learn 워크플로우를 scriptable하게 만들 수 없음.
2. **Channel encoding 결함**:
   - **(a)** `send_cc` / `send_note` / `send_chord` / `send_program_change`: `0...16` 허용 + 직접 `0x0F` masking → `channel=16` → wire 0 (Ch 1). off-by-one.
   - **(b)** `send_pitch_bend` / `send_aftertouch`: 채널 검증 자체가 부재 (`params["channel"].flatMap(UInt8.init) ?? 0` raw 캐스팅 — `CoreMIDIChannel.swift:201,212`). `channel: 17` 입력 시 UInt8 truncate + engine `& 0x0F` → silent corruption. (a)보다 더 큰 문제.
   - **(c)** `play_sequence` / `record_sequence`의 `notes` 문자열 format `pitch,offsetMs,durMs[,vel[,ch]]`의 `ch` 필드는 `NoteSequenceParser.swift:14`에서 `UInt8 // 0..15` 명시. 사용자 입장에서 다른 6종과 일관성 없음.
3. **Docs misleading**: `docs/SETUP.md §4`가 Logic 12.2에서 작동하지 않는 `.plist` Import 경로를 1차 안내. `Scripts/install.sh:235`도 동일. `Scripts/install-keycmds.sh` + `Scripts/keycmd-preset.plist` 헤더 주석도 동일. 사용자 25분+ 시행착오 후 GitHub issue 작성하게 됨.
4. **Homebrew install 차단**: `depends_on xcode` 가 CLT-only host에서 brew install 차단. ADHOC 사전 빌드 바이너리 다운로드라 build-time Xcode 의존 불필요.
5. **MIDIKeyCommands 채널 부분 redundancy**: `MIDIKeyCommandsChannel.swift:34-108`의 `mappingTable` audit 결과:
   - **다른 dispatcher로 cover됨**: transport/edit/project/navigate 계열 (Undo/Redo/Cut/Copy/Paste/Save/Quantize/Split/Play/Stop/Record/Goto 등)
   - **부분 cover**: track 계열은 `logic_tracks` (PRD v0.1 누락 cite), automation 계열은 `logic_tracks.set_automation`
   - **다른 path 없음 (channel-only)**: `note.up_semitone` / `note.up_octave` / `note.down_semitone` / `note.down_octave` (4종) — 다른 dispatcher case 분기에 노출 안 됨, CGEvent mapping 없음
   - **부분만 다른 path 있음**: `view.toggle_*` 계열은 일부만 dispatcher 노출 (mixer/library/inspector 등)
   - 따라서 "All covered" 단순 문구는 부정확 — audited matrix로 교체 필요.

### 1.3 Impact of Not Solving
- 신규 사용자가 SETUP.md 따라가다가 Logic 12.2 화면에서 `.plist` 파일 회색 처리 발견 → 25분+ 손실 후 포기 또는 수동 binary install로 우회 (보고자 케이스)
- `channel:16` 보낸 자동화 스크립트가 실제로는 Ch 1로 송신 → silent wrong-channel routing → 디버깅 어려움
- `pitch_bend channel: 100` 같은 잘못된 입력이 silent UInt8 truncate → 더 깊은 wrong-channel
- "MIDIKeyCommands channel ready"라는 health 보고가 거짓 → AI 에이전트가 채널 신뢰하고 작업 진행 → 실제 동작 안 함
- `note.up_octave` 등 channel-only 동작이 docs에서 "use logic_edit instead"로 잘못 안내될 경우 사용자가 막힘
- Homebrew 사용자 install 차단 → adoption 저해

## 2. Goals & Non-Goals

### 2.1 Goals (v0.3 재정렬)
- [ ] **G1**: `logic_midi.send_*` 6종 + `play_sequence`에 `port` 파라미터 추가 (`"midi"|"keycmd"`, default `"midi"` for backward compat). 7 ops × 2 ports = 14 routingTable entries. **`record_sequence`는 port 비지원** (NG7 — SMF import path는 KeyCmd port 의미 없음). manual MIDI Learn 워크플로우 scriptable.
- [ ] **G2**: 모든 MIDI channel 입력 의미를 1-based(1..16, music convention)로 통일. 0/17+/non-integer 입력 시 invalid_params 반환. wire byte = `(channel - 1) & 0x0F`. 적용 범위: send_* 6종 + play_sequence + record_sequence (`NoteSequenceParser` API 타입 변경 — `Result<[ParsedNote], NoteSequenceParseError>`).
- [ ] **G_NEW (v0.3)**: ChannelRouter readiness gate가 `midi.*.keycmd` 오퍼레이션을 manual_validation_required 채널에 대해서도 통과시키도록 router-level bypass allowlist 도입. KeyCmd 채널 미승인 환경에서도 KeyCmd 포트로의 MIDI 송신은 가능 (Manual MIDI Learn seeding이 사용자 승인 전 단계의 핵심 use case이므로).
- [ ] **G3**: SETUP.md / TROUBLESHOOTING.md / Scripts/install.sh / Scripts/install-keycmds.sh / Scripts/keycmd-preset.plist 헤더 모두 재작성. Import 경로 제거, manual MIDI Learn 2+ 예시 + 시간 소요 명시 + audited coverage matrix.
- [ ] **G4**: Homebrew formula `depends_on xcode` 제거 (ADHOC binary는 build 의존 없음). `Formula/logic-pro-mcp.rb` 코멘트로 ADHOC-only path 명시.
- [ ] **G5**: MIDIKeyCommands 채널 health detail 메시지 정직화 — "Manual MIDI Learn required + audited coverage matrix link + channel-only ops 명시(note.up_*/down_*)".
- [ ] **G6**: 후방 호환성 보장 — 기존 `port` 미지정 호출은 이전과 동일 동작 + 동일 에러 메시지 wording 유지. channel encoding 변경은 1-based 정렬이 명시적 BREAKING change로 CHANGELOG + Issue #1 자동 댓글 + GitHub Release notes에 BEFORE/AFTER 표 형태로 명시.
- [ ] **G7**: Issue #1 자동화 — `Scripts/release.sh`에 `gh issue comment 1` + `gh issue close 1` 단계 추가 (또는 release notes에서 Issue close link).

### 2.2 Non-Goals
- **NG1**: `--install-keycmds` Swift CLI subcommand (보고자 방안 1) — `.logikcs` schema 리버스 + `MROF` chunk 직접 inject는 큰 작업이며 Logic preferences 직접 수정 위험. v3.2 PRD로 분리.
- **NG2**: MIDIKeyCommands 채널 완전 제거 — backward compat 유지. 외부 사용자가 manual binding 완료한 경우 계속 작동해야 함. 단 health에서 redundancy + channel-only ops 명시.
- **NG3**: Manual MIDI Learn UI 자동화 (AppleScript/AX로 Controller Assignments 패널 조작) — Logic의 Controller Assignments는 AX 노출 한정, 실용적 자동화 불가. 별도 R&D 영역.
- **NG4**: 다른 채널(Scripter, MCU)의 redundancy 평가 — 이번 PRD 범위 외.
- **NG5 (v0.2 신규)**: `port: "scripter"` 옵션 미포함. ScripterChannel은 `plugin.set_param`/`mixer.set_plugin_param` 전용 (`ScripterChannel.swift:46-48` execute guard), `midi.send_*` 처리 책임 없음. v3.1.5는 `port: "midi" | "keycmd"` 두 값만 지원. Scripter port 라우팅이 필요해지면 별도 PRD에서 ScripterChannel transport 확장 + JSFX rec policy 검토 필요.
- **NG6 (v0.2 신규)**: `note.up_*` / `note.down_*` 등 mappingTable에 등재되었으나 어떤 dispatcher case에도 노출되지 않은 **orphan ops**의 dispatcher entry 신규 추가 — 별도 follow-up issue로 추적. v3.1.5 docs는 "orphan — not reachable from any logic_* tool today; manual MIDI Learn binding이 유일한 호출 path" 정직 명시만.
- **NG7 (v0.3 신규)**: `record_sequence`에 `port` 파라미터 비지원. `record_sequence`는 SMF import path (TrackDispatcher 소속)이며 가상 MIDI 포트 송신과 무관. `port` 파라미터를 입력하면 dispatcher-level enum validation에서 reject (silent ignore 폐기 — v0.2 E14 결정 번복). channel 1-based만 적용 대상.
- **NG8 (v0.3 신규)**: `mmc_play` / `mmc_stop` / `mmc_record` / `mmc_locate` / `send_sysex` / `step_input` / `create_virtual_port`은 `port` 파라미터 비지원. dispatcher-level enum validation에서 입력 시 reject. `mmc_*`는 SysEx broadcast로 모든 청취 device 대상이며 KeyCmd port 의미 없음. `send_sysex`/`step_input`/`create_virtual_port`도 별도 책임.

## 3. User Stories & Acceptance Criteria

### US-1: Scriptable manual MIDI Learn flow
**As a** AI agent operator, **I want** `logic_midi.send_cc` 가 어느 가상 MIDI 포트로 송신할지 선택 가능, **so that** Logic의 Controller Assignments → Learn Mode를 통해 MIDIKeyCommands 바인딩을 자동화 스크립트로 seed할 수 있다.

**Acceptance Criteria:**
- [ ] **AC-1.1**: `logic_midi.send_cc {controller: 6, value: 127, channel: 16, port: "keycmd"}` 호출 시 메시지가 `LogicProMCP-KeyCmd-Internal` 가상 포트로 송신된다. 검증: (a) unit test — KeyCmd transport handle invocation 확인 (`MIDIKeyCommandsChannel.transport.send` 호출 검증), (b) 라이브 — Logic 12.2 Controller Assignments → Learn Mode 활성화 후 `port:"keycmd"` 송신 → 입력으로 `LogicProMCP-KeyCmd-Internal` 캡처 확인 (보고자 환경 + Isaac 환경 양쪽에서).
- [ ] **AC-1.2**: `port` 미지정 시 기존 라우팅 100% 보존 — `MIDI-Internal` 포트로 송신 + 동일 에러 메시지 wording (regression test로 string-equality 검증).
- [ ] **AC-1.3**: 유효하지 않은 `port` 값(`"foo"` / `"scripter"` / `""` 등) 입력 시 **dispatcher-level enum validation** → State C `invalid_params` + hint `"port must be one of: midi, keycmd"`. Channel-side에 도달하지 않음.
- [ ] **AC-1.4**: `send_note` / `send_chord` / `send_program_change` / `send_pitch_bend` / `send_aftertouch` / `play_sequence` 모두 동일 `port` 파라미터 적용. 일관된 라우팅 (**7개 entry point — v0.3에서 record_sequence 제외**, NG7 참조).
- [ ] **AC-1.5**: Tool description (manifest.json + `MIDIDispatcher.description`)에 정확한 문구 포함: `"port: virtual MIDI source selection (\"midi\" default | \"keycmd\" — for manual MIDI Learn seeding); channel: MIDI channel number 1..16 (1-based) — independent from port"`. play_sequence의 `notes` 문자열 안 `ch` 필드는 entry-level `port` 파라미터와 별개임을 docstring에 명시.
- [ ] **AC-1.6 (v0.3 신규)**: `port` 파라미터 비지원 ops(record_sequence / mmc_* / send_sysex / step_input / create_virtual_port)에 `port` 입력 시 dispatcher-level validation에서 State C `invalid_params` + hint `"port parameter not supported for <op_name>"` 반환. silent ignore 금지.
- [ ] **AC-1.7 (v0.3 신규)**: ChannelRouter readiness gate에 `midi.*.keycmd` operation key bypass allowlist 도입. `MIDIKeyCommandsChannel.healthCheck()` 가 `available: true, ready: false` (manual_validation_required) 인 상태에서도 `midi.*.keycmd` 오퍼레이션은 execute에 도달 가능. `available: false` 인 상태(virtual port 미생성)에서는 여전히 차단 + State C `port_unavailable` 반환.

### US-2: Honest 1-based MIDI channel encoding (BREAKING)
**As a** caller, **I want** `channel: 16` 가 실제로 MIDI Channel 16으로 송신되도록, **so that** Logic의 channel 표시와 input 의미가 일치한다.

**Acceptance Criteria:**
- [ ] **AC-2.1**: `channel: 16` 입력 시 wire status byte의 lower nibble = `0xF` (Logic이 Ch 16으로 표시). 적용: send_cc / send_note / send_chord / send_program_change / send_pitch_bend / send_aftertouch + play_sequence/record_sequence parser.
- [ ] **AC-2.2**: `channel: 1` 입력 시 wire lower nibble = `0x0` (Logic이 Ch 1로 표시).
- [ ] **AC-2.3**: `channel: 0` 또는 `channel: 17+` 입력 시 State C `invalid_params` 반환 + hint: `"channel must be 1..16 (1-based)"`.
- [ ] **AC-2.4**: Non-integer channel (`channel: 1.5`) 입력 시 strict integer parser로 reject → `invalid_params` + hint: `"channel must be integer 1..16"`. 현재 `intParam`은 JSON `1.5` (`Value.double` 케이스) 입력에서 `intValue == nil` + `stringValue == nil` → silent default fall-through. **v3.1.5 fix**: `MIDIDispatcher` 내 신규 helper `validateMidiChannel(_:)`이 raw `Value` 타입을 case-switch로 검사 — `.int(let n)` 만 통과, `.double(let f)`이면 `Int(exactly: f)` 시도 후 round-trip 일치 시 통과 (예: 1.0 OK, 1.5 reject), `.string(let s)`이면 `Int(s)` 시도. 모든 경로에서 1..16 범위 검증.
- [ ] **AC-2.5**: pitch_bend / aftertouch는 현재 검증 자체가 부재 → 신규 `midiChannel(_:)` 검증 함수 일관 적용 + State C envelope 표준화.
- [ ] **AC-2.6 (v0.4 보강)**: BREAKING change communication step:
  - CHANGELOG **표 #1 — top-level `channel:` parameter** (send_* 6종 + play_sequence):
    ```
    | input        | v3.1.4 wire    | v3.1.5 wire | Logic display |
    |--------------|----------------|-------------|---------------|
    | channel:1    | 0x?0 (ch1)     | 0x?0 (ch1)  | Ch 1 (unchanged) |
    | channel:16   | 0x?0 (ch1)     | 0x?F (ch16) | Ch 16 (CHANGED — was Ch 1) |
    | channel:0    | 0x?0 (ch1)     | error       | invalid_params |
    | channel:17   | 0x?1 (truncate)| error       | invalid_params |
    | channel:1.5  | 0x?0 (default) | error       | invalid_params (strict integer) |
    ```
  - CHANGELOG **표 #2 — `notes` substring `ch` field** (play_sequence + record_sequence parser, Loop 3 Boomer P1-3):
    ```
    | input fragment        | v3.1.4 behavior        | v3.1.5 behavior |
    |-----------------------|------------------------|-----------------|
    | "60,0,500,127,0"      | wire ch1 (0 → wire 0)  | parse error (ch=0 invalid in 1-based) — whole parse fails |
    | "60,0,500,127,1"      | wire ch2 (1 → wire 1)  | wire ch1 (1-based: ch1 → wire 0) — CHANGED |
    | "60,0,500,127,15"     | wire ch16 (15 → wire 0xF) | wire ch15 (1-based: ch15 → wire 0xE) — CHANGED |
    | "60,0,500,127,16"     | invalid (out of 0..15) → silent default | wire ch16 (1-based: ch16 → wire 0xF) — NEW VALID |
    | "60,0,500,127" (omit) | wire ch1 (default 0)   | wire ch1 (default 1-based ch1) — unchanged |
    | "60,0,500,127,17"     | invalid → silent default | parse error — whole parse fails |
    ```
    Migration: 사용자 자동화 스크립트가 `notes` 안 `ch` 필드를 0-based wire 값으로 사용했다면 1씩 증가 필요. ch=0은 무효 (Ch1을 의미하려면 `ch=1`). 또한 NoteSequenceParser가 partial parse silent fall-through에서 strict whole-parse-fail로 변경됨 — invalid 세그먼트 1개라도 있으면 전체 호출 실패 (`Result<[ParsedNote], NoteSequenceParseError>`).
  - GitHub Release notes에 prominent `### ⚠️ BREAKING` 섹션 + 두 표 모두 포함
  - Issue #1 자동 comment + close (release.sh 단계 추가)
  - Tool description (`MIDIDispatcher.description` + `TrackDispatcher.description`)에 "channel: 1..16 (1-based)" inline 명시. play_sequence/record_sequence는 추가로 "`notes` ch field also 1-based since v3.1.5" 명시.

### US-3: Honest documentation for Logic 12.2
**As a** new user, **I want** SETUP.md가 Logic 12.2 실제 동작과 일치하는 안내를 제공, **so that** 25분+ 시행착오 없이 단계별로 진행 가능하다.

**Acceptance Criteria:**
- [ ] **AC-3.1**: `docs/SETUP.md` 의 모든 `.plist` Import 안내가 완전히 제거된다 (해당 섹션 §, MIDIKeyCommands 관련 모든 곳).
- [ ] **AC-3.2**: Manual MIDI Learn step-by-step 가이드가 **최소 2개 예시** binding (반복 패턴 명시 — 예: `Edit > Undo` 1번, `Track > New Audio Track` 1번)으로 작성. 각 단계마다 Logic UI 클릭 위치 + MCP 호출 명령(`port:"keycmd"` 포함) + screenshot 또는 상세 문구. Learn 패널 진입/탈출 cycle + Save Assignments 단계 모두 포함.
- [ ] **AC-3.3**: 시간 소요 명시 (예: "최소 binding: ~2분 (1개), 전체 권장 binding: ~25분 (48개) — 단 channel-only ops만 binding하는 minimal path 권장 ~5분").
- [ ] **AC-3.4 (v0.3 정정)**: **Audited coverage matrix** — `MIDIKeyCommandsChannel.swift:34-110` mappingTable 실측 검증된 행만 등재. 단순 "all covered" 문구 금지. 4-column matrix:
  ```
  | mappingTable op (CC#)        | dispatcher entry exposing it    | router primary fallback     | requires keycmd binding? |
  |------------------------------|---------------------------------|-----------------------------|--------------------------|
  | edit.undo (30) / redo (31)   | logic_edit.undo / .redo         | accessibility, applescript  | NO — optional            |
  | edit.cut/copy/paste/select_all | logic_edit                    | accessibility, cgevent      | NO — optional            |
  | edit.quantize/join/duplicate/split/normalize/delete/bounce_in_place | logic_edit | accessibility, cgevent | NO — optional |
  | edit.toggle_step_input       | logic_edit.toggle_step_input    | midiKeyCommands, cgevent    | RECOMMENDED              |
  | project.save / save_as / bounce | logic_project                | applescript                 | NO — optional            |
  | transport.toggle_cycle (72)  | logic_transport.toggle_cycle    | midiKeyCommands, accessibility | RECOMMENDED          |
  | transport.capture_recording (73) | (no other dispatcher entry) | midiKeyCommands only        | YES                      |
  | transport.toggle_metronome / toggle_count_in (98/99) | logic_transport | midiKeyCommands, accessibility | RECOMMENDED         |
  | track.create_audio / create_instrument / create_external_midi / duplicate / delete / create_stack / create_drummer | logic_tracks | midiKeyCommands, cgevent | RECOMMENDED |
  | view.toggle_mixer/piano_roll/library/inspector/score_editor/step_editor (50-51, 55-56, 59, 48) | logic_navigate.toggle_view | midiKeyCommands, cgevent | RECOMMENDED |
  | nav.goto_marker / create_marker / delete_marker / zoom_to_fit / set_zoom_level | logic_navigate | midiKeyCommands, cgevent | RECOMMENDED |
  | automation.set_mode (84)     | logic_tracks.set_automation     | mcu (primary), midiKeyCommands, cgevent | RECOMMENDED  |
  | automation.toggle_view (85)  | logic_navigate.toggle_view {automation} | midiKeyCommands, cgevent (`.key(0)`) | RECOMMENDED  |
  ```
  **Orphan ops 별도 섹션** (mappingTable + routingTable 등재되었으나 어떤 dispatcher case에도 노출 안 됨 — Loop 3 boomer P1-4 검증 결과 추가):
  - `note.up_semitone (90)` / `note.down_semitone (91)` / `note.up_octave (92)` / `note.down_octave (93)` — manual MIDI Learn binding 가능하나 어떤 logic_* tool로도 호출 path 없음.
  - `view.toggle_smart_controls (54)` / `view.toggle_plugin_windows (58)` / `view.toggle_automation (57, 별도 — automation.toggle_view (85)와 다름)` — `NavigateDispatcher.swift:112-128` switch가 `mixer / piano_roll / score / step_editor / library / inspector / automation` 7개만 라우팅. `smart_controls`/`plugin_windows`는 dispatcher 노출 없음. `view.toggle_automation` (CC 57)은 mappingTable에 있으나 dispatcher의 `automation` view-key는 `automation.toggle_view` (CC 85) — 별도 op.
  - `transport.capture_recording (73)` — cgEvent에 매핑 없음 (`CGEventChannel.swift:115` 미존재). routingTable는 `[.midiKeyCommands, .cgEvent]`이나 cgEvent에서 unmapped → 사실상 keycmd-only.
  - **AC 결정 (v0.4)**: Orphan ops는 dispatcher entry 추가 follow-up issue (NG6) 등록 + docs에서 "manual binding 가능하나 자동 호출 path 없음 (현재 orphan)" 명시. `transport.capture_recording`은 cgEvent unmapped로 사실상 keycmd-only인 점 별도 명시 (orphan은 아니나 binding 사실상 필수).

  Matrix는 docs/SETUP.md `§MIDIKeyCommands coverage`에 명시 + manifest.json `description` link.
- [ ] **AC-3.5**: `docs/TROUBLESHOOTING.md`에서 Logic 12.2 `.plist` import 회색 처리 증상 + manual MIDI Learn 정직 안내. v3.1.4 이전 SETUP 따라간 사용자에 대한 migration 안내.
- [ ] **AC-3.6**: 다음 4개 파일에서 misleading "Import" 안내 모두 제거:
  - `Scripts/install.sh` (line ~235 Import 안내)
  - `Scripts/install-keycmds.sh` (출력 메시지)
  - `Scripts/keycmd-preset.plist` 헤더 주석
  - `docs/SETUP.md` (해당 섹션)

### US-4: Homebrew install on CLT-only host
**As a** user with Command Line Tools but no full Xcode, **I want** `brew install logic-pro-mcp` 가 차단 없이 진행, **so that** ADHOC 바이너리를 정상 다운로드 + 설치할 수 있다.

**Acceptance Criteria:**
- [ ] **AC-4.1**: `Formula/logic-pro-mcp.rb` 의 `depends_on xcode: ["15.0", :build]` 라인이 제거된다. 코멘트로 "ADHOC pre-built binary download — no source-build, no Xcode dependency. Source build via Package.swift requires Xcode 15.0+ but is not the supported install path." 명시.
- [ ] **AC-4.2**: `depends_on :macos => :sonoma` 는 유지 (런타임 OS 요구사항).
- [ ] **AC-4.3**: Formula `test do` 블록(`shell_output "#{bin}/LogicProMCP --check-permissions"`)은 유지 — Xcode 없이도 통과해야 함.
- [ ] **AC-4.4**: `brew audit --strict --new-formula Formula/logic-pro-mcp.rb` 로컬 통과. 로컬 검증 명령은 release notes에 명시.
- [ ] **AC-4.5**: `brew style Formula/logic-pro-mcp.rb` 로컬 통과.

### US-5: Honest channel readiness reporting
**As a** AI agent reading `logic_system.health`, **I want** MIDIKeyCommands channel detail이 정직하게 redundancy + 수동 설정 필요성 + channel-only ops를 보고, **so that** 채널을 신뢰하고 매핑되지 않은 명령 보내는 사고를 방지한다.

**Acceptance Criteria:**
- [ ] **AC-5.1 (v0.3 정정)**: `MIDIKeyCommands` 채널 health `detail` 메시지가 다음을 포함:
  - virtual MIDI port 상태 ("`LogicProMCP-KeyCmd-Internal` is ready")
  - "Manual MIDI Learn required — see docs/SETUP.md §<section>"
  - "Most preset operations are covered by logic_edit / logic_project / logic_navigate / logic_tracks / logic_transport — see audited coverage matrix in SETUP.md"
  - "Effectively keycmd-only (cgEvent fallback unmapped): `transport.capture_recording`. Manual MIDI Learn binding required for actual function activation."
  - "Orphan ops in mappingTable (no MCP tool currently exposes call path): `note.up_semitone`, `note.up_octave`, `note.down_semitone`, `note.down_octave`, `view.toggle_smart_controls`, `view.toggle_plugin_windows`, `view.toggle_automation` (CC 57; distinct from `automation.toggle_view` CC 85). Manual binding possible but MCP has no caller path; tracked in NG6 follow-up."
- [ ] **AC-5.2**: `verification_status` 는 그대로 `manual_validation_required` 유지 (라이브 검증 불가능한 사실 변경 없음). `available: true`, `ready: false` 는 그대로.
- [ ] **AC-5.3**: 채널 자체는 deprecate 하지 않음 (사용자 manual binding 완료 케이스 backward compat).
- [ ] **AC-5.4**: Health detail 길이는 < 1 KB per channel (envelope size 검증).

## 4. Technical Design

### 4.1 Architecture Overview (v0.2 — Dispatcher-level direct routing)

```
                 ┌─────────────────────────────────────────┐
                 │ MIDIDispatcher (logic_midi)             │
                 │   send_cc / send_note / send_chord /    │
                 │   send_program_change / pitch_bend /    │
                 │   send_aftertouch / play_sequence /     │
                 │   record_sequence                       │
                 │                                         │
                 │ 1) port enum validation                 │
                 │    ("midi" | "keycmd"; default "midi")  │
                 │ 2) channel 1-based validation           │
                 │    (1..16, integer; reject 0/17+/float) │
                 │ 3) operation key 분기:                   │
                 │    port="midi"   → "midi.send_cc"       │
                 │    port="keycmd" → "midi.send_cc.keycmd"│
                 └────────────┬────────────────────────────┘
                              │
                              ▼
                 ┌─────────────────────────────────────┐
                 │ ChannelRouter.routingTable          │
                 │   "midi.send_cc": [.coreMIDI]       │
                 │   "midi.send_cc.keycmd":            │
                 │       [.midiKeyCommands]            │
                 │   ... (7 entry × 2 port = 14 entries; record_sequence 제외 NG7) │
                 │                                     │
                 │ 단일 채널 직접 라우팅 — fallthrough │
                 │ 문제 / terminal State C 충돌 없음   │
                 └────────────┬────────────────────────┘
                              │
                ┌─────────────┴─────────────┐
                ▼                           ▼
    ┌──────────────────────┐   ┌──────────────────────────┐
    │ CoreMIDIChannel      │   │ MIDIKeyCommandsChannel   │
    │ engine →             │   │ transport →              │
    │ MIDI-Internal        │   │ KeyCmd-Internal          │
    └──────────────────────┘   └──────────────────────────┘
```

**라우팅 결정 (v0.3 — readiness bypass 추가)**:

1. MIDIDispatcher가 `port` 파라미터 enum validation
2. 미지정 시 `"midi"` default
3. operation key를 `"midi.send_cc"` 또는 `"midi.send_cc.keycmd"` 로 직접 분기 (suffix 패턴 채택 — dynamic dictionary 옵션 폐기)
4. ChannelRouter.routingTable에 정적 entries 추가 — **7 ops × 2 ports = 14개 routing entries** (record_sequence 제외, NG7)
5. MIDIKeyCommandsChannel.execute에 `midi.send_*.keycmd` operation case 추가 (mappingTable 외 신규 직접 송신 path)
6. **(v0.3 신규)** ChannelRouter에 `bypassReadinessOps: Set<String>` 신규 field 추가. **7 ops × keycmd suffix만** 등록 — `["midi.send_cc.keycmd", "midi.send_note.keycmd", "midi.send_chord.keycmd", "midi.send_program_change.keycmd", "midi.send_pitch_bend.keycmd", "midi.send_aftertouch.keycmd", "midi.play_sequence.keycmd"]`. `route()`의 readiness gate가 이 set에 포함된 operation은 `ready: false`도 통과 (manual_validation_required 채널이라도 가능).
7. **(v0.4 신규 — Loop 3 Boomer P1-2 해소)** `available: false` (virtual port 미생성) 분기에서 ChannelRouter가 직접 `HonestContract.encodeStateC(error: .portUnavailable, hint: health.detail, extras: ["operation": op])` 반환. `.portUnavailable`은 `terminalErrorCodes` 등록되어 fallback chain에서 wrapping되지 않음 (다음 채널로 넘어가지 않음). 일반 ops는 기존 `lastError` 누적 + "All channels exhausted" 메시지 유지 (backward compat).

**Readiness bypass rationale (v0.4 chicken-and-egg framing — Loop 3 Guardian P2-2 해소)**: Manual MIDI Learn seeding은 정의상 채널 승인 *전* 단계 (`--approve-channel MIDIKeyCommands` 호출 전). 사용자가 처음 v3.1.5 시작 → KeyCmd 채널 `available:true / ready:false`(manual_validation_required) → bypass 없으면 어떤 `*.keycmd` op도 실행 불가 → Manual MIDI Learn binding 자체가 시작될 수 없음. **Chicken-and-egg**: bypass 없으면 사용자가 channel을 활성화하기 위한 binding을 만들 방법이 없음. bypass는 이 lock-in을 푸는 유일한 메커니즘. `--approve-channel` 호출 후 `runtimeReady`가 되면 bypass 영향 무관 (어차피 readiness 통과). 일반 라우팅(`midi.send_cc` → coreMIDI primary)은 readiness 검사 그대로 유지.

**ScripterChannel 미포함 (NG5)**: `port: "scripter"` 옵션은 v3.1.5 범위 외. ScripterChannel은 plugin parameter 송신 전용으로 transport / scope 다름.

**record_sequence 미포함 (NG7)**: SMF import path (TrackDispatcher 소속), KeyCmd port 의미 없음. dispatcher-level enum validation에서 `port` 입력 시 invalid_params reject.

### 4.2 Data Model Changes
없음. 코드 레벨 변경만. routingTable에 entries 추가는 in-memory dictionary.

### 4.3 API Design

#### 변경: `logic_midi.send_*` 6종 + `play_sequence` + `record_sequence`

**기존 (v3.1.4)**:
```jsonc
{
  "controller": 30,        // 0..127
  "value": 127,            // 0..127
  "channel": 16            // 0..16 — 16은 wire 0으로 wrap (off-by-one)
                            // pitch_bend/aftertouch는 검증 부재 (UInt8 raw)
}
```

**v3.1.5**:
```jsonc
{
  "controller": 30,        // 0..127 — unchanged
  "value": 127,            // 0..127 — unchanged
  "channel": 16,           // 1..16 (BREAKING: 0/17+/float now invalid_params)
  "port": "keycmd"         // optional, default "midi"
                            // values: "midi" | "keycmd"
                            // "scripter" deferred (NG5)
}
```

#### Dispatcher 변경 명세

`Sources/LogicProMCP/Dispatchers/MIDIDispatcher.swift` 변경:

```swift
// 신규 helper
private static func validatePort(_ params: [String: Value]) -> Result<String, String> {
    let port = stringParam(params, "port", default: "midi")
    let validPorts = ["midi", "keycmd"]
    guard validPorts.contains(port) else {
        return .failure("port must be one of: \(validPorts.joined(separator: ", "))")
    }
    return .success(port)
}

private static func validateMidiChannel(_ params: [String: Value]) -> Result<UInt8, String> {
    // v0.3 strict integer check — reject floats like 1.5
    // Value type case-switch needed because Value.intValue accepts JSON int
    // but JSON double (`1.5`) returns nil, then stringValue also nil →
    // fall-through to default (silent corruption — AC-2.4 violation).
    guard let raw = params["channel"] else {
        // optional — default to channel 1 (1-based)
        return .success(0) // wire byte; Ch 1 in 1-based
    }
    let intCandidate: Int? = {
        switch raw {
        case .int(let n): return n
        case .double(let f):
            // accept whole-number doubles (1.0), reject fractional (1.5)
            return Int(exactly: f)
        case .string(let s): return Int(s)
        default: return nil
        }
    }()
    guard let v = intCandidate else {
        return .failure("channel must be integer 1..16 (1-based)")
    }
    guard (1...16).contains(v) else {
        return .failure("channel must be integer 1..16 (1-based)")
    }
    return .success(UInt8(v - 1)) // wire nibble 0..15
}

private static func operationKey(base: String, port: String) -> String {
    return port == "midi" ? base : "\(base).\(port)"
}

// case "send_cc" 변경
case "send_cc":
    switch validatePort(params) {
    case .failure(let msg): return toolTextResult(HonestContract.encodeStateC(error: .invalidParams, hint: msg, ...), isError: true)
    case .success(let port):
        switch validateMidiChannel(params) {
        case .failure(let msg): return toolTextResult(HonestContract.encodeStateC(error: .invalidParams, hint: msg, ...), isError: true)
        case .success(let wireChannel):
            return await routedTextResult(router, operation: operationKey(base: "midi.send_cc", port: port), params: [
                "controller": String(intParam(params, "controller")),
                "value": String(intParam(params, "value")),
                "channel": String(wireChannel),  // wire byte 0..15
            ])
        }
    }
// 6종 send_* + play_sequence 동일 패턴 — record_sequence는 NG7로 port 입력 시 invalid_params reject (E14, AC-1.6)
```

#### ChannelRouter 변경 명세

`Sources/LogicProMCP/Channels/ChannelRouter.swift` `routingTable`에 추가:

```swift
"midi.send_cc": [.coreMIDI],
"midi.send_cc.keycmd": [.midiKeyCommands],
"midi.send_note": [.coreMIDI],
"midi.send_note.keycmd": [.midiKeyCommands],
// ... 8 ops × 2 ports
```

#### MIDIKeyCommandsChannel 변경 명세

`Sources/LogicProMCP/Channels/MIDIKeyCommandsChannel.swift`에 신규 case 추가:

```swift
func execute(operation: String, params: [String: String]) async -> ChannelResult {
    // 기존 mappingTable lookup logic 유지
    // 신규 case — direct MIDI send via KeyCmd transport (manual MIDI Learn 시드용)
    switch operation {
    case "midi.send_cc.keycmd":
        // wire bytes 직접 구성 후 transport.send 호출
        // HC envelope (State B readback_unavailable — KeyCmd transport는 echo 없음)
    case "midi.send_note.keycmd":
        // ...
    // 8 ops
    default:
        // 기존 mappingTable lookup
    }
}
```

#### Tool description 변경

`MIDIDispatcher.swift:7` description 업데이트:
```
"... send_cc/program_change/pitch_bend/aftertouch -> controller payloads (channel: 1..16 (1-based), port: \"midi\"|\"keycmd\" default \"midi\"); ..."
```

| Method | Operation key (port="midi") | Operation key (port="keycmd") |
|--------|-----------------------------|-------------------------------|
| send_cc | midi.send_cc | midi.send_cc.keycmd |
| send_note | midi.send_note | midi.send_note.keycmd |
| send_chord | midi.send_chord | midi.send_chord.keycmd |
| send_program_change | midi.send_program_change | midi.send_program_change.keycmd |
| send_pitch_bend | midi.send_pitch_bend | midi.send_pitch_bend.keycmd |
| send_aftertouch | midi.send_aftertouch | midi.send_aftertouch.keycmd |
| play_sequence | midi.play_sequence | midi.play_sequence.keycmd |

> **record_sequence (v0.3 NG7)**: SMF import path, TrackDispatcher 소속, KeyCmd port 의미 없음. `port` 파라미터 입력 시 dispatcher-level validation에서 invalid_params reject. v3.1.5에서 channel 1-based 적용은 `NoteSequenceParser` API 변경(아래)을 통해 `record_sequence` 진입점에도 적용.

#### TrackDispatcher 변경 명세 (v0.3 신규)

`Sources/LogicProMCP/Dispatchers/TrackDispatcher.swift` (record_sequence 진입점):
- `record_sequence` case에 `port` 파라미터 입력 시 invalid_params reject (NG7).
- `notes` 문자열 파싱은 `NoteSequenceParser.parse(notes:)` API 변경 영향 받음 — 신규 `Result<[ParsedNote], NoteSequenceParseError>` 타입 핸들링.

#### NoteSequenceParser API 변경 (v0.3 신규)

`Sources/LogicProMCP/MIDI/NoteSequenceParser.swift`:

```swift
// 기존 (v3.1.4):
static func parse(_ notes: String) -> [ParsedNote]
// 신규 (v3.1.5):
enum NoteSequenceParseError: Error {
    case channelOutOfRange(segment: String, value: Int)
    case invalidPitch(segment: String)
    case invalidTiming(segment: String)
    // ...
}
static func parse(_ notes: String) -> Result<[ParsedNote], NoteSequenceParseError>

// ParsedNote.channel field semantics 변경:
// 기존: UInt8 // 0..15 (wire value)
// 신규: UInt8 // 0..15 (wire value) — input은 1..16 (1-based)에서 변환
//        partial parse가 silent default-handle 하지 않음
```

호출부 변경 필요:
- `Sources/LogicProMCP/Dispatchers/TrackDispatcher.swift` — `record_sequence` SMF generation
- `Sources/LogicProMCP/Channels/CoreMIDIChannel.swift` — `play_sequence` real-time playback (line ~279)
- 양쪽 모두 `.failure` 시 State C `invalid_params` + hint 반환.

### 4.4 Key Technical Decisions (v0.2 갱신)

| # | Decision | Options Considered | Chosen | Rationale |
|---|----------|-------------------|--------|-----------|
| D1 | Port routing 위치 | (A) Channel-side fallthrough / (B) Dispatcher-level direct | **B** | (A)는 ChannelRouter terminal State C 차단 + manual_validation_required skip과 충돌. v0.1 review에서 P1 발견. dispatcher-level이 라우팅 의미론 명확. |
| D2 | Channel 1..16 enforcement | (A) Strict reject 0 / (B) Lenient — 0도 ch 1 매핑 / (C) Dual-mode (deprecation cycle) | **A** | Issue #1-3 정확한 fix. silent wrong-channel 재발 방지. (C)는 매력적이나 단일 release cycle에 끝내는 것이 명확. |
| D3 | Backward compat for `port` | (A) Required param / (B) Optional default "midi" | **B** | 기존 호출 영향 0 + 동일 에러 메시지 wording. |
| D4 | Port enum 값 | (A) `"midi"|"keycmd"|"scripter"` / (B) `"midi"|"keycmd"` only | **B** | ScripterChannel은 plugin param 전용, midi.send_* 처리 책임 없음. v3.1.5 범위에서 제외. |
| D5 | MIDIKeyCommands 채널 처리 | (A) Deprecate + 제거 / (B) Deprecate flag만 / (C) 유지 + audited matrix | **C** | 외부 사용자 manual binding 완료 케이스 보호. note.up_*/down_* 등 channel-only ops 존재. health detail로 정직 보고. |
| D6 | 1-based migration | (A) Silent / (B) BREAKING + CHANGELOG | **B** | Silent는 디버깅 악몽. CHANGELOG BEFORE/AFTER 표 + Issue #1 자동 댓글 + tool description inline. |
| D7 | Homebrew xcode 의존 | (A) 완전 제거 / (B) `:optional` | **A** | ADHOC release는 사전 빌드 바이너리. depends_on :macos => :sonoma 만 충분. |
| D8 | Channel encoding scope | (A) send_* 6종만 / (B) send_* + play_sequence + record_sequence | **B** | 동일 dispatcher 안 인코딩 일관성. PRD v0.1 review에서 P1. |
| D9 | "All covered" docs 표현 | (A) 단순 문구 / (B) Audited coverage matrix | **B** | mappingTable 일부는 다른 dispatcher path 없음 (note.up_*). 정직한 matrix 필수. |
| D10 | Issue #1 자동화 | (A) 수동 댓글 / (B) release.sh에 gh comment + close 단계 | **B** | 외부 사용자 communication 누락 방지 자동화. |

## 5. Edge Cases & Error Handling (v0.2 보강)

| # | Scenario | Expected Behavior | Severity |
|---|----------|-------------------|----------|
| E1 | `port: "foo"` (invalid) | Dispatcher-level validation → State C `invalid_params` + hint: "port must be one of: midi, keycmd" | P1 |
| E2 | `port: "scripter"` | E1과 동일 (NG5 — v3.1.5 비지원) + hint에 "scripter port deferred to future release" | P2 |
| E3 | `port: "midi"` 명시 + 기존 callers | 기존 동작과 100% 동일 (CoreMIDIChannel 라우팅, 동일 에러 메시지 wording) | P0 |
| E4 | `channel: 0` | State C `invalid_params` + hint: "channel must be integer 1..16 (1-based)" — BREAKING | P1 |
| E5 | `channel: 17` | E4와 동일 hint | P1 |
| E6 | `channel: 1.5` (float) | Strict integer parser → State C `invalid_params` + hint | P2 |
| E7 (v0.3 정정) | `port: "keycmd"` + KeyCmd virtual port 미초기화 (startup race) | `MIDIKeyCommandsChannel.healthCheck().available == false` 또는 `transport.readiness().available == false` 체크 → State C `port_unavailable` (HonestContract.FailureError 신규 case + terminalErrorCodes에 추가) + hint: "LogicProMCP-KeyCmd-Internal not yet published; check logic_system.health" | P1 |
| E8 (v0.3 정정) | `port: "keycmd"` + 채널이 `manual_validation_required` 상태 (사용자 미승인) | **router-level bypass allowlist** (AC-1.7) 적용 → dispatcher-level direct routing이 readiness gate를 통과하여 execute 도달. KeyCmd virtual port 자체가 published면 송신 가능. 일반 라우팅(`midi.send_cc` → coreMIDI primary)은 readiness 검사 그대로 유지. | P1 |
| E9 | Manual binding 완료한 외부 사용자가 v3.1.4 `channel:16` 입력 → v3.1.5 wire 변경 | (a) v3.1.4에서 ch16 입력 → wire 0x?0 (Ch 1) 매칭 binding이라면 v3.1.5에서 break. (b) ch16 입력 → 의도대로 ch16 매칭 binding이라면 v3.1.4에서는 작동 안 했을 것 (wire wrap → ch1 send) → 사실상 (a)만 가능. CHANGELOG BEFORE/AFTER 표로 명시 + 사용자에게 "v3.1.5 업그레이드 후 manual binding 1회 재바인딩 필요" 안내. | P1 |
| E10 | Homebrew formula `xcode` 제거 후 brew audit | `brew audit --strict --new-formula Formula/logic-pro-mcp.rb` 로컬 PASS | P1 |
| E11 | brew bottle CI re-build (있다면) | ADHOC binary download path 명시 → bottle/source-build 비지원 명기 | P2 |
| E12 | SETUP.md 업데이트 후 신규 사용자 따라감 | Manual MIDI Learn 2개 예시로 최소 2 binding 성공 + 5분~25분 추정 명시 | P1 |
| E13 | Health detail이 길어져 JSON envelope size 초과 | 현재 envelope size ~200 bytes → 새 detail ~600 bytes 예상 (audited matrix link 포함). < 1KB 한도 검증 unit test. | P2 |
| E14 (v0.3 변경) | `record_sequence` / `mmc_*` / `send_sysex` / `step_input` / `create_virtual_port`에 `port` 입력 | dispatcher-level enum validation에서 즉시 reject → State C `invalid_params` + hint: `"port parameter not supported for <op_name>"`. silent ignore 폐기 (NG7/NG8). | P2 |
| E15 | release.sh 실행 시 `gh issue comment 1` 실패 | release 자체는 성공으로 마침 + warning. Issue 댓글은 manual fallback (release notes에 명시 link 보유). | P2 |

## 6. Security & Permissions
변경 없음. 모든 dispatch는 server-local. `port` enum string membership check은 권한 우회 / DoS 벡터 없음.

## 7. Performance & Monitoring

| Metric | Target | Measurement |
|--------|--------|-------------|
| `send_cc` 호출 latency (p95) | < 5ms (CoreMIDI port write) | 라이브 검증 |
| `port` 분기 overhead | < 0.1ms (dispatcher level enum check) | unit test 측정 |
| Health detail size | < 1 KB per channel | E13 unit test |

### 7.1 Monitoring & Alerting
- **No remote telemetry**: logic-pro-mcp는 server-local + stdio MCP. Log.debug stderr only.
- `port: "keycmd"` 사용 빈도는 사용자 자체 보고에 의존.
- Channel routing 실패는 router-level warn log (subsystem: "router").

## 8. Testing Strategy

### 8.1 Unit Tests (TDD Spec)
- `MIDIDispatcherSendCCPortTests.swift` (NEW)
  - testSendCCDefaultPortRoutesToMidiSendCCOperation
  - testSendCCKeycmdPortRoutesToMidiSendCCKeycmdOperation
  - testSendCCInvalidPortReturnsStateCInvalidParams
  - testSendCCScripterPortRejectedAsNotSupported (E2)
- `MIDIDispatcherChannelEncodingTests.swift` (NEW)
  - testChannel1MapsToWireZero
  - testChannel16MapsToWireFifteen
  - testChannel0Rejected
  - testChannel17Rejected
  - testFloatChannelRejected (E6)
  - testMissingChannelDefaultsToCh1Wire0
- `MIDIDispatcherEntryPointConsistencyTests.swift` (NEW, v0.4 정정)
  - testAllSendOpsAcceptPortParam (**7 ops × 2 ports = 14 cases** parametrized — record_sequence 제외, NG7)
  - testAllSendOpsValidateChannel1Based
  - testRecordSequenceRejectsPortParam (E14, NG7 — silent ignore 폐기, invalid_params reject)
  - testMmcOpsRejectPortParam (NG8 — mmc_*/sysex/step_input/create_virtual_port)
  - testRoutingTableInvariant — 모든 `^midi\..*\.keycmd$` routing key가 `bypassReadinessOps` set에 포함됨을 검증 (Loop 3 Guardian P2-1 수정 — parallel-list trap 방지)
- `NoteSequenceParserTests.swift` (확장)
  - testNoteSequenceChChannelIs1Based
  - testNoteSequenceCh0Rejected
  - testNoteSequenceCh17Rejected
- `MIDIKeyCommandsChannelDirectSendTests.swift` (NEW)
  - testKeyCmdChannelHandlesSendCCKeycmdOperation
  - testKeyCmdChannelTransportNotPublishedReturnsPortUnavailable (E7)
- `ChannelRouterRoutingTableTests.swift` (확장)
  - testRoutingTableContainsAllSendOpsKeycmdVariants
- `HealthDispatcherTests.swift` (확장)
  - testKeyCmdChannelDetailIncludesManualLearnHint
  - testKeyCmdChannelDetailMentionsCoverageMatrix
  - testKeyCmdChannelDetailListsChannelOnlyOps
  - testKeyCmdChannelDetailUnderOneKB (E13)
- `BackwardCompatRegressionTests.swift` (NEW)
  - testSendCCWithoutPortMatchesPriorBehavior (E3 — string-equality of error messages)
  - testRoutingTableMidiSendCCKeyUnchanged

### 8.2 Integration Tests
- 기존 `MIDIDispatcherTests` 의 `port` 미지정 호출이 모두 PASS (backward compat regression).
- `ChannelRouterTests`에 routing entries 추가 검증.

### 8.3 Edge Case Tests
- E1-E15 모두 unit test 케이스로 커버.
- E9 manual binding compat — live verification only (Isaac 환경 + 보고자 환경).
- E10/E11 brew test — 로컬 `brew audit --strict --new-formula` 통과 + Isaac CI/dev에서 검증.
- E12 docs — review-time validation (Phase 6 strategist+guardian).

### 8.4 Live Verification Required (v0.2 신규, v0.3 release-blocker 기준 추가)
다음 시나리오는 unit test로 커버 불가 → release 전 라이브 검증 필수:
1. **AC-1.1 라이브**: Logic 12.2 Controller Assignments → Learn Mode 진입 → MCP에서 `port:"keycmd"` 송신 → `LogicProMCP-KeyCmd-Internal` 입력으로 캡처 확인.
2. **AC-2.1 라이브**: `channel:16` 송신 → Logic UI에서 Ch 16 표시 확인.
3. **AC-3.2 라이브**: SETUP.md의 Manual MIDI Learn 2개 예시 step-by-step 실제 따라가서 binding 성공 확인.
4. **AC-4.1/4.4/4.5 라이브**: CLT-only host 시뮬 또는 Isaac 환경에서 `brew install logic-pro-mcp` 통과 확인.
5. **E9 라이브**: v3.1.4 + manual binding 완료 환경에서 v3.1.5 업그레이드 → 기존 binding 동작 / 재바인딩 필요 케이스 명시.

**Release blocker 기준 (v0.3 신규)**:
- 시나리오 **1, 2, 4 PASS 필수** — release block. 실패 시 v3.1.5 release 보류.
- 시나리오 **3** — Isaac follow-along 1회 PASS + 보고자 재검증 by Issue close 시점. 일부 step 모호 시 docs revision 후 재검증.
- 시나리오 **5** — TROUBLESHOOTING.md migration note 추가로 acceptable. release block 아님 (docs ship + 사용자에게 재바인딩 안내).

## 9. Rollout Plan

### 9.1 Migration Strategy (v0.2 강화)
- v3.1.4 → v3.1.5 binary 자동 호환 (backward compat for `port` 미지정).
- **BREAKING for channel encoding**:
  - CHANGELOG에 BEFORE/AFTER 표 (AC-2.6)
  - GitHub Release notes prominent `### ⚠️ BREAKING` 섹션 + migration table
  - Issue #1 자동 comment via `Scripts/release.sh` (AC-2.6, G7)
  - Issue #1 자동 close
  - Tool description (`MIDIDispatcher.description`) inline "channel: 1..16 (1-based)"
  - `LogicProMCP --check-permissions` 출력에 v3.1.5 BREAKING 한 줄 reminder (1회만)
- Homebrew formula 변경: v3.1.5 release 시 새 formula 자동 갱신 (release.sh가 Formula sha256 업데이트). brew audit local 검증 (AC-4.4).

### 9.2 Feature Flag
N/A. 모든 변경 v3.1.5 즉시 적용.

### 9.3 Rollback Plan
- 사용자가 v3.1.4 다운그레이드 가능 — Homebrew tap에 v3.1.4 tag 보존됨.
- channel encoding regression 발견 시 v3.1.6 hotfix.
- Manual binding 사용자 break 시 (E9): docs/TROUBLESHOOTING.md에 "v3.1.5 업그레이드 후 manual binding 재구성" 1-page 안내.

## 10. Dependencies & Risks (v0.2 보강)

### 10.1 Dependencies
| Dependency | Owner | Status | Risk if Delayed |
|-----------|-------|--------|-----------------|
| MIDIKeyCommandsChannel `KeyCmdTransportProtocol` | 내부 | 기존 코드 | 없음 (transport.send 가능) |
| ChannelRouter routingTable in-memory | 내부 | 기존 코드 | 없음 |
| HonestContract `FailureError` enum 확장 (`portUnavailable` 신규) | 내부 | 신규 추가 필요 | external envelope parser가 unknown reason gracefully ignore 가정 (low risk) |
| `gh` CLI authenticated for Issue #1 comment | Isaac local | active | release.sh 자동화 — 실패 시 manual fallback (E15) |
| Homebrew tap repo write access | Isaac | 활성 | release.sh 자동 push |

### 10.2 Risks
| # | Risk | Probability | Impact | Mitigation |
|---|------|------------|--------|------------|
| R1 | Channel encoding 변경이 외부 manual-binding 사용자 break (E9) | Medium | High | CHANGELOG BEFORE/AFTER 표 + Issue #1 자동 댓글 + 보고자 사전 알림 + TROUBLESHOOTING.md migration |
| R2 | dispatcher-level routing이 routingTable 키 폭증 (16 entries) | Low | Low | suffix 패턴 일관 — readability OK. Unit test가 모든 entry 검증 |
| R3 | Docs 재작성이 모호한 step 포함 | Medium | Medium | Phase 6 strategist+guardian 리뷰 + 라이브 검증 (AC-3.2 step-by-step) |
| R4 | Homebrew formula 변경이 brew audit 실패 | Low | Low | local `brew audit --strict --new-formula` + `brew style` 검증 (AC-4.4/4.5) |
| R5 | brew bottle CI re-build 차단 (있다면) | Low | Low | ADHOC binary download path 명시 코멘트 — bottle/source-build 비지원 명기 (E11) |
| R6 | port enum 미래 확장 (e.g. `"scripter"` 추가) | Low | Low | enum 자체는 string-based — 미래 확장 시 새 case 추가 + routingTable entry 추가만 |
| R7 | HonestContract FailureError 확장이 외부 envelope parser break | Low | Medium | "unknown reason gracefully ignore" 가정 명시 in CHANGELOG |
| R8 (v0.3 강화) | Issue #1 자동 댓글이 reporter 알림 폭주 (재오픈 시 v3.1.6+ 가 재댓글) | Low | Low | release.sh가 `gh issue view 1 --json state` 로 OPEN 상태일 때만 댓글 + close 시도. CLOSED면 skip. v3.1.5 release.sh가 close 후 만약 reporter가 reopen하면 향후 release는 새 issue 댓글로 분기 (자동 재close 금지). |
| R9 | Manual MIDI Learn 2개 예시가 부족 | Medium | Medium | docs review에서 Isaac이 follow-along 1회 + 보고자 follow-along 요청 |

## 11. Success Metrics

| Metric | Baseline | Target | Measurement Method |
|--------|----------|--------|--------------------|
| GitHub Issue #1 closure | OPEN | CLOSED with v3.1.5 release link | Issue tracker |
| 신규 사용자 setup time-to-first-success | ~25 min (보고자) | ≤ 10 min (manual MIDI Learn 안내 명확화) | 보고자 재테스트 요청 |
| `port:"keycmd"` adoption | N/A | 1+ 외부 사용 사례 (3개월 내) | 사용자 자체 보고 |
| Channel encoding 사용자 confusion | 1+ 보고됨 | 0 (BREAKING change 명시 + invalid_params hint) | future GitHub issues |
| Tests: pass count | 917 (post-v3.1.5 thomas-doesburg) | 1000+ (+85 tests minimum across T1-T8) | swift test --no-parallel |
| Tests: backward compat regression | 0 fail | 0 fail | BackwardCompatRegressionTests |

## 12. Open Questions (v0.2 갱신)

- [x] **OQ-1**: `port` 파라미터 값 네이밍 — `"midi"` 가 generic하지만 사용자 친화적. 결정 유지. tool description에 "default port (CoreMIDI virtual source for general MIDI output)" inline 명시.
- [x] **OQ-2**: Health detail 길이. 결정: 단일 `detail` string + < 1 KB 한도 (E13).
- [x] **OQ-3**: 모든 48 commands binding 의무? 결정: NO. minimal path (channel-only ops만) 권장 + audited matrix 명시.
- [x] **OQ-4 (v0.2 신규)**: `port: "scripter"` 미래 추가 시 ScripterChannel 확장? 결정: 별도 PRD에서 검토. v3.1.5 NG5에 명시.
- [x] **OQ-5 (v0.2 신규)**: `record_sequence`에 `port` 의미 없음 — silent ignore vs reject? 결정: warning log + ignore (E14, backward compat).
- [x] **OQ-6 (v0.2 신규)**: `note.up_*` / `view.toggle_*` 등 channel-only ops에 dispatcher path 신규 추가? 결정: NG6, follow-up issue로 분리.
- [x] **OQ-7 (v0.3 결정)**: HonestContract `FailureError`에 `portUnavailable` case 추가 — minor bump (v3.1.5)에서 enum 추가 OK + `terminalErrorCodes`에도 등록 (router fallback chain wrapping 방지). CHANGELOG에 명시: "New FailureError: `port_unavailable` (terminal). External envelope parsers must gracefully ignore unknown reasons; documented as part of HonestContract minor evolution policy." Migration: 외부 envelope 파서 영향 검증 — v3.1.4에 `port_unavailable` 케이스 트리거 path 자체가 없었으므로 사실상 추가만 발생, 기존 응답 변경 없음.

---
