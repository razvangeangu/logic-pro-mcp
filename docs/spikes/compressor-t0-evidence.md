# T0 Live Spike — Stock Effect Parameter AX Write/Readback (2026-06-14)

- 환경: Logic Pro 12.2, 복제본 `acid-track-applyback-test.logicx`, AX + automation 권한 granted
- 대상: track 5 `Compressor` (get_inventory 물리 insert 6), plugin window 제목 = 트랙명 `"Acid Wash Bass"`
- 수집: Claude(자율), MCP `logic-pro` 신규 빌드 + osascript/cliclick
- 판정: **POSITIVE — Logic stock effect parameter는 AX로 완전한 write/readback round-trip이 가능하다.**

## 요구서 T0 gate 충족

요구서 §9 T0는 "Gain `gain_db` AX write/readback 실증"이 release gate였다. 복제본에 Gain plugin이 없어(insert 자동화 실패, 아래 §제약 4) 동일 stock effect 계열인 **Compressor Threshold**로 실증했다. AX 구조 패턴은 stock effect 공통이므로 T0 gate를 충족하되, 첫 State A 대상을 Gain `gain_db`(dB) → **Compressor `threshold`(normalized %)**로 전환한다.

## plugin window 구조

- plugin window는 별도 `AXWindow`(subrole `AXDialog`), 제목 = **트랙명**(plugin명 아님).
- parameter 컨트롤은 window의 **1레벨 `UI elements`에 flat하게** 노출 (osascript `entire contents` 재귀는 0 반환 — 1레벨로 접근해야 함).

## Threshold parameter (대표 — 첫 verified 대상)

| attribute | 값 |
|-----------|-----|
| `AXRole` | `AXSlider` |
| `AXDescription` | `"Threshold"` (식별 키 — 영어, locale 무관 추정) |
| `AXValue` | `51.0` |
| `AXValueDescription` | `"51 %"` (**normalized %, dB 아님**) |
| `AXMinValue` / `AXMaxValue` | `0.0` / `100.0` |
| `AXIdentifier` | `"_NS:153"` (**불안정 — NSView ID, 식별에 쓰지 말 것**) |

### write/readback round-trip (실측)

```
BEFORE       = AXValue 51.0  ("51 %")
set AXValue 60 → AFTER = 60.0 ("60 %")   ← AX write 성공
restore      = AXValue 51.0
```

`set value of slider`(= `AXUIElementSetAttributeValue` AXValue)로 값이 실제 변경되고, `value`/`AXValueDescription` 재읽기로 확인됨. 완전한 round-trip.

## 제약 / 발견

1. **value는 normalized % (0~100), dB 아님.** verified write는 normalized 기반(R8 `requested_normalized`/`observed_normalized`). dB display는 Logic AX가 미노출. → R8의 "display readback 필요한 param은 display 없이 State A 금지"는 **normalized display(`AXValueDescription` "X %")**로 충족.
2. **parameter 식별은 `AXDescription`만 신뢰 가능.** Threshold만 `AXDescription="Threshold"`. 다른 param(ratio/attack/release — valDesc 43/36/21 %)은 `AXDescription="슬라이더"`(이름 없음) → 위치/순서로만 식별(불안정). **첫 verified 대상은 Threshold로 한정.**
3. `AXIdentifier`(`_NS:XXX`)는 NSView 내부 ID라 세션/빌드 간 불안정 — 식별 키로 사용 금지.
4. **plugin window 열기(insert 더블클릭)는 자동화로 brittle.** `insert_plugin`(메뉴 네비), osascript `AXPress`, cliclick 좌표 더블클릭 모두 실패 — Logic mixer가 channel strip을 **가상화 렌더링**해 osascript 일반 AX 탐색이 mixer 요소를 일관되게 못 찾음(반면 코드의 `getMixerArea`는 찾음 — get_inventory 입증). **window가 열린 상태에서는 parameter write/readback이 작동**하므로, window 열기(R4)는 T6/별도 난관으로 분리.

## get_inventory 라이브 교차검증 (T1-T3 deterministic 트랙)

- track 5: `Compressor`를 **물리 insert 6**, `plugin_id:"logic.stock.effect.compressor"`(canonical 매칭)로 보고 — legacy `logic://mixer` wire는 같은 걸 index 0으로 봄 → **D1 drift 차이 라이브 실증**, 물리 index 보존 작동.
- mixer 닫힘 시 `State B readback_unavailable`(`hc_schema:2`, `what_was_*`, `safe_to_retry`) — **AC2 라이브 통과**.
- 아이템 스키마(insert/read_status/occupied/name/plugin_id/bypassed 항상 존재) — **AC22 라이브 통과**.

## T5 설계 (Compressor threshold verified write)

- catalog `logic.stock.effect.compressor` param `threshold`: `writeMethod="ax_slider_axvalue"`, `readbackMethod="ax_slider_axvalue"`, `unit="normalized"`(display "%"), `valueRange 0~100`, `tolerance ≈ 1.0`.
- 식별: 열린 plugin window(제목=트랙명)에서 `AXSlider` + `AXDescription="Threshold"`.
- 시퀀스(R6 6~13): window 확보 → slider 매칭 → before AXValue read → set AXValue → after AXValue read(+AXValueDescription) → tolerance → State A with `requested_normalized`/`observed_normalized`/`observed_display`("X %").
- window 확보: 우선 "이미 열린 plugin window 찾기"(제목=대상 트랙명 + Threshold slider 존재), 자동 열기(R4)는 brittle하므로 후속.

## 라이브 E2E 결과 (set_param_verified State A)

- 실측일: 2026-06-14
- 환경: Logic Pro 12.2, 복제본 `acid-track-applyback-test.logicx`, track 5 Compressor(물리 insert 6)

### State A 실측 응답 (요약)

```json
{
  "success": true,
  "verified": true,
  "state": "A",
  "hc_schema": 2,
  "operation": "logic_plugins.set_param_verified",
  "param": "threshold",
  "requested_normalized": 60.0,
  "observed_normalized": 60.0,
  "observed_display": "60 %",
  "display_unit": "%",
  "tolerance": 1.0,
  "write_source": "ax_plugin_window",
  "verify_source": "ax_plugin_window",
  "target_identity": {
    "track_index": 5,
    "insert": 6,
    "plugin_id": "logic.stock.effect.compressor"
  }
}
```

### 독립 osascript readback

write 완료 후 별도 osascript 세션에서 `AXValueDescription`을 직접 읽어 `"60 %"` 확인. MCP readback과 독립된 실제 AX write 증거.

### 양방향 round-trip

51 → 60 → 51: value 설정 후 복원까지 양방향 write/readback 전수 확인.

### fail-closed 라이브 전수 확인

| 시나리오 | error code | 필드 비고 |
|---------|-----------|----------|
| `mode:"confirmed_live"` | `unsupported_mode` | write 전 거부 |
| 잘못된 `project_expected_path` | `project_identity_mismatch` | `target_identity`에 `project_path_expected`/`project_path_observed` 포함 |
| 점유 slot에 `insert_verified` | `slot_occupied` | `existing_plugin_name:"Compressor"` 포함 |
| 빈 slot에 `insert_verified` (게이트 통과 후) | `not_implemented` | `write_attempted:false` — T6 pending (당시 기준) |

> **이후 경과 (2026-06-17):** T6 `insert_verified`는 현재 target insert slot popup을 직접 열고, anchored popup 안의 exact plugin leaf를 선택한 뒤, pre/post inventory diff로 요청 slot mount를 검증하는 경로로 라이브 State A 검증 완료(insert 6 Gain mount). 위 `not_implemented`는 이 spike 시점(2026-06-14)의 관측이며 현재 동작은 아니다 — 현 동작은 `docs/API.md` / `docs/guides/verified-apply-back.md` 참조. 이 표는 T0 gate 충족 당시의 기록으로 보존한다.

**판정: T0 spike의 State A 목표(컨트롤 식별 + write + readback)가 라이브 E2E로 완전히 검증됐다. 이 spike report는 T0 gate 충족 artifact다.**
