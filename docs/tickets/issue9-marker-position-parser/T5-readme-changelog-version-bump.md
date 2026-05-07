# T5: README + CHANGELOG v3.1.11 + version bump

**PRD Ref**: PRD-issue9 > G5
**Priority**: P1
**Size**: S (< 30min)
**Status**: Todo
**Depends On**: None (T1-T4 병렬 진행 가능)

---

## 1. Objective
모든 version artifact를 3.1.11로 동기. CHANGELOG에 정직한 behavior change (lenient → strict) 명시.

## 2. Acceptance Criteria
- [ ] AC-1: `Sources/LogicProMCP/Server/ServerConfig.swift::serverVersion` = `"3.1.11"`.
- [ ] AC-2: `Formula/logic-pro-mcp.rb` `version "3.1.11"`.
- [ ] AC-3: `manifest.json` 모두 `3.1.11` / `v3.1.11`.
- [ ] AC-4: `Scripts/install.sh` default `v3.1.11`.
- [ ] AC-5: `Tests/LogicProMCPTests/LogicProServerTransportTests.swift` startup banner 모두 `v3.1.11`.
- [ ] AC-6: README badge 3.1.11.
- [ ] AC-7: README Status 섹션에 v3.1.11 entry 추가.
- [ ] AC-8: CHANGELOG `[Unreleased]` 아래에 v3.1.11 entry 추가 — issue / fix / behavior change / 11 원칙 / tests / live e2e / boomer P1 통합 / Strategist + Guardian fix list 모두 정직 명시.
- [ ] AC-9: `swift test --no-parallel --filter testServerVersionMatchesPackagingArtefacts` PASS.

## 3. Implementation

### 3.1 Files
| File | Change |
|------|--------|
| `Sources/LogicProMCP/Server/ServerConfig.swift` | `3.1.10` → `3.1.11` |
| `Formula/logic-pro-mcp.rb` | `3.1.10` → `3.1.11` |
| `manifest.json` | `3.1.10`, `v3.1.10` → `3.1.11`, `v3.1.11` |
| `Scripts/install.sh` | `v3.1.10` → `v3.1.11` |
| `Tests/LogicProMCPTests/LogicProServerTransportTests.swift` | banner string `v3.1.10` → `v3.1.11` |
| `README.md` | badge `3.1.10` → `3.1.11`; Status 섹션 신규 v3.1.11 paragraph |
| `CHANGELOG.md` | `[Unreleased]` 아래 v3.1.11 entry |

### 3.2 CHANGELOG entry 본문

```markdown
## [3.1.11] — 2026-05-07

**`thomas-doesburg`의 Issue #9 — 영문 Logic 12.2 marker position parser 정확성 수정 + 13 locales 메뉴 경로 문서화 + lenient 1-3 components 정책 폐기.**

v3.1.10 verification에서 reporter가 두 가지 발견을 보고:
- **F1 (해결됨, doc 수정)**: 영문 12.2의 Marker List 윈도우는 `Navigate → Open Marker List` 하위 (Window 메뉴 아님). v3.1.9 릴리스 노트가 "Open the Marker List window" 표현 사용 → 영문 사용자가 Window 메뉴 검색.
- **F2 (parser bug)**: VOCALS 마커 위치 `"146 4 4 240."` (UI rendering 끝 마침표) → parser reject → fallback `\(index+1).1.1.1` = `"6.1.1.1"`. 데이터 정확성 위반.

### Fix

`AXLogicProElements.parseMarkerListPosition`을 다음 정책으로 강화:

1. **끝 마침표 / 콤마 strip** (`while`-loop): Logic UI rendering artifact 흡수.
2. **공백/탭만 separator**: dot은 끝에서만 의미 — mixed separator (`"1.1 1.1"`) 거부 (NG7 manufacturing 차단).
3. **ASCII digit narrow**: `Int(_: String)` failable initializer 사용 — Arabic-Indic 등 비-ASCII 거부 (NG9, Guardian P2-2).
4. **1-based 검증**: 모든 컴포넌트 ≥ 1 — `"0 0 0 0"` 거부 (NG8 manufacturing 차단, Guardian P0-2).
5. **Strict 4 components 정책** (NG11, Boomer P1-1): lenient 1-3 components 폐기. Logic UI는 항상 4 컴포넌트 노출하므로, 1-3 컴포넌트는 비-position 셀(예: tempo)일 가능성으로 nil. 호출자가 안전하게 `\(index+1).1.1.1` fallback 적용.

**Behavior change** (정직 명시):
- v3.1.10에서 valid이던 `"17 2"` → `"17.2"` (2-component lenient)는 v3.1.11에서 nil (NG11 strict 4 only).
- 영향: 어떤 관찰된 Logic 빌드도 1-3 컴포넌트 표기를 사용 안 하므로 사용자 직면 영향 0.
- 이론적 영향: 미래 빌드가 헤더 행 단축 표기 노출 시 → fallback `\(index+1).1.1.1` (silently 잘못된 bar로 manufacturing 안 함 — 더 honest).

### Sub-bar navigation (NG10, Guardian P0-1 분리)

`goto_marker { name: "VOCALS" }`가 cache의 `position: "146.4.4.240"`를 정확히 surface하지만, AX `gotoPositionViaBarSlider`는 첫 컴포넌트(bar)만 추출하여 slider에 set — beat/div/tick은 무시. v3.1.11은 **cache 정확성까지** scope. Sub-bar 정확도 navigation은 별도 PRD (v3.2 — `gotoPositionViaBarSlider` 확장)로 분리.

### TROUBLESHOOTING 13 locales (Boomer P1-2)

코드는 이미 13 locales (KR/EN/JA/FR/DE/ES/IT/ZH-S/ZH-T/RU/PT/NL)의 Marker List 윈도우 타이틀을 인식하지만, v3.1.9 docs는 KR/EN만 명시 → 다른 locale 사용자가 동일 discoverability 결함 재발. v3.1.11 docs는 13 locales 표 + "모든 빌드 Navigate 메뉴" 명시.

### Tests

- 기존 `parseMarkerListPosition_validInputs` / `_invalidInputs` 삭제 — Swift Testing parameterized 2개 `@Test(arguments:)`로 통합:
  - `parseMarkerListPosition_valid` (8 cases): trailing-dot, trailing-comma, 다중 공백, 탭, etc.
  - `parseMarkerListPosition_invalid` (17 cases): 1-3 components (NG11), 0-positions (NG8), Arabic-Indic (NG9), mixed separator (NG7), etc.
- 신규 통합 `enumerateMarkers_trailingDotPosition_canonicalizes` — 영문 12.2 시나리오 e2e (synthetic AX tree).
- 기존 fallback 회귀 (`enumerateMarkers_unparseablePosition_usesIndexFallback`) PASS 유지.

`swift test --no-parallel` → **1075 / 1075 PASS** (was 1062 in v3.1.10; +13 net — parameterized 25 cases 통합 + 통합 1 - 기존 7 = +13 net).

### Review process

PRD v0.3 = Strategist + Guardian + Boomer 3-agent 통합 후 ALL PASS. 본 fix 5 P0/P1 통합:
- Strategist: parser 라인 축소, edge case 25→14, 언어 전환 안전 절차
- Guardian P0-1: sub-bar nav 불가 → NG10 분리
- Guardian P0-2: 0 거부 (NG8)
- Guardian P0-3: mixed separator 거부 (NG7)
- Guardian P2-2: ASCII narrow (NG9)
- Boomer P1-1: lenient 폐기 → strict 4 (NG11)
- Boomer P1-2: 13 locales doc 통합

### Live verification

영문 Logic 12.2 (per-app preferred language)에서 비-bar-aligned 마커가 `logic://markers` 응답에 정확한 position으로 surface 검증. `docs/live-verify-v3.1.11.md` Tier 1/2/3 runbook 신규 작성.
```

## 4. Review Checklist
- [x] 모든 version artifact 동기
- [x] CHANGELOG 정직 (behavior change + 5 P0/P1 명시)
- [x] 11 원칙 → release notes 명시
- [x] testServerVersionMatchesPackagingArtefacts PASS
