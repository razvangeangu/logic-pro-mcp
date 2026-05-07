# PRD: Marker List Position Parser 정확성 + 영문 Logic 12.2 메뉴 경로 (Issue #9)

**Version**: 0.3 (Phase 2 review 3-agent 완전 통합 — Approved)
**Author**: Claude (자율 — Isaac 위임)
**Date**: 2026-05-07
**Status**: Approved
**Size**: **M** (변경 범위) / Review depth: **XL** (사용자 지시 — 4-agent review + 라이브 e2e + 11 원칙)
**Issue**: [#9 — v3.1.10 logic://markers returns [] on English Logic 12.2](https://github.com/MongLong0214/logic-pro-mcp/issues/9)

**v0.3 변경사항** (Boomer P1 통합):
- Boomer P1-1: **Lenient 1-3 components 정책 폐기** → 4 components strict. 이유: Logic UI는 항상 4 components 노출, 1-3은 미관찰. Tempo/BPM 셀이 미래에 `"120"`으로 노출되면 silently wrong bar navigation 위험. 11 원칙 "0.1% 엣지케이스 0" + "오버엔지니어링 금지"와 정합 (사용 안 하는 lenient 유지는 데드코드 + 위험).
- Boomer P1-2: TROUBLESHOOTING 메뉴 경로를 13 locales에 적용 — 코드는 이미 모든 locale 지원, 문서만 KR/EN 한정이었음. NG5 폐기, AC-3.1 확장.

**v0.2 변경사항** (Phase 2 strategist + guardian):
- Strategist: Size XL → M (review depth만 XL); parser line 축소; edge case 25 → 15; §8.3 언어 전환 정정
- Guardian P0-1: AC-1.5 sub-bar navigation 불가 → NG10 분리 (v3.2 별도 PRD: `gotoPositionViaBarSlider` 확장)
- Guardian P0-2: E22 `"0 0 0 0"` → nil (1-based)
- Guardian P0-3: dot separator 미지원 (Logic은 공백만)
- Guardian P2-2: ASCII digit narrow (`Int(_:String)`)
- Guardian P1-1: AC measurability 강화

---

## 1. Problem Statement

### 1.1 Background

Issue #9 (`thomas-doesburg`) 두 가지 발견:

**(F1) 메뉴 경로 차이 — 해결됨, 문서만 보강 필요**
- 한글 12.2: `탐색 → 마커 목록 열기` (Navigate)
- 영문 12.2: `Navigate → Open Marker List` (Window 메뉴 아님)
- v3.1.9 릴리스 노트가 "Open the Marker List" 표현 사용 → 영문 사용자가 Window 메뉴 검색.

**(F2) 비-bar-aligned 마커 position 부정확**
- 6 markers 중 5개는 `bar.1.1.1` (whole-bar)이라 정상 surface.
- VOCALS는 `"146 4 4 240."` (영문 빌드 UI 끝 마침표) — parser reject → fallback `\(index+1).1.1.1` = `"6.1.1.1"`.
- **데이터 정확성 위반**: `logic://markers`가 UI에 표시된 위치와 다른 거짓 위치 surface.

### 1.2 Problem Definition

`AXLogicProElements.parseMarkerListPosition`이 영문 Logic 12.2의 비-bar-aligned 위치 표기 (`"<bar> <beat> <div> <tick>."` — UI rendering 끝 마침표 포함)를 reject하여 호출자가 fallback `(index+1).1.1.1`을 사용한다. 결과적으로 `MarkerState.position`이 **데이터 정확성 측면에서 거짓**.

### 1.3 Impact of Not Solving

- **Cache 데이터 신뢰성**: consumer가 `logic://markers`의 position을 grid 분석/automation/section labelling에 사용. 거짓 위치가 silently 흘러감.
- **Parser fix 범위는 cache까지만**: `goto_marker { name }` navigation은 v3.1.10에서 `transport.goto_position`으로 라우팅하지만 그 AX 구현(`gotoPositionViaBarSlider`)은 **bar 수준만** navigate (line 2208/2218/2231). sub-bar 정확도 navigation은 NG10에서 명시적으로 분리.
- **신뢰 누적 손상**: Issue #7→#8→#9의 reporter가 매 릴리스 직후 verified report 제출. 빠르고 정직한 닫음이 가장 중요.

---

## 2. Goals & Non-Goals

### 2.1 Goals

- [ ] **G1**: `parseMarkerListPosition`이 다음 입력을 모두 정확히 canonical `"bar.beat.div.tick"`로 변환:
  - `"1 1 1 1"` (한글 빌드 whole-bar)
  - `"146 4 4 240"` (영문 빌드 비-bar-aligned)
  - **`"146 4 4 240."`** (영문 빌드 UI rendering 끝 마침표 — 이번 fix 핵심)
  - `"146 4 4 240,"` (방어 — 끝 콤마)
  - `"  146 4 4 240  "` / `"146  4  4  240"` / `"146\t4\t4\t240"` (공백 noise)
  - `"17 2 3 4"` (정확히 4 components — strict policy v0.3)
- [ ] **G2**: 잘못된 입력에 대해 **정직한 nil**:
  - `""` / `"   "` / `"."` (빈 / 의미 없음)
  - `"abc"` / `"1 abc"` (혼합 비숫자)
  - `"1"` / `"17 2"` / `"1 2 3"` (1-3 components — Boomer P1-1 strict 4 only)
  - `"1 2 3 4 5"` / `"1 2 3 4 5 6"` (5+ components)
  - `"0 0 0 0"` / `"0 1 1 1"` (Logic 1-based 위반 — manufacturing data 차단)
  - `"١٤٦ ٤ ٤ ٢٤٠"` (Arabic-Indic 숫자 — Logic 미지원)
  - `"1.1 1.1"` (mixed dot+space separator — manufacturing 위험)
- [ ] **G3** (cache scope): `logic://markers` 응답의 모든 position이 Logic UI 표시와 정확히 일치 (영문/한글 12.2 모두).
- [ ] **G4** (test count): 1062 → ≥ 1075 PASS. 신규 ≥ 13 (parser 매트릭스 + 통합 + 회귀).
- [ ] **G5** (docs): TROUBLESHOOTING.md에 KR/EN 메뉴 경로 표 + Window 메뉴 부재 경고. README Status v3.1.11 entry.
- [ ] **G6** (코드 품질, 측정 가능):
  - `swift build -c release` 0 warnings
  - parser 본문 ≤ 20 lines (doc 주석 제외)
  - 모든 신규/수정 코드 한글 주석
  - `git grep -E '(TODO|FIXME|XXX)' Sources/` 신규 0건
  - 11 원칙 4-agent 리뷰에서 P0/P1 0건

### 2.2 Non-Goals

- **NG1**: Marker List 외부 surface (Lists window `D` 키, floating Marker Set window) 스크레이핑 — 정식 메뉴 경로로 워크플로 충분.
- **NG2**: 콤마 separator (`"1,2,3,4"`) — 어떤 빌드도 미사용. 단 끝 콤마는 trailing-strip 대상에 포함.
- **NG3**: SMPTE 형식 (`HH:MM:SS:FF`) — Marker List는 항상 musical grid.
- **NG4**: AXTable visible-row-order 기반 `id` ordering — 의도된 동작.
- **NG5** (Boomer P1-2 제거): ~~KR/EN 외 locale 메뉴 경로~~ → 폐기. 코드는 이미 13 locales 지원하므로 문서도 동일 범위로 확장 (AC-3.1 참조).
- **NG6**: Auto-open Marker List (`LOGIC_PRO_MCP_AUTO_OPEN_MARKER_LIST=1`) — 명시적 opt-in 시까지 deferred.
- **NG7** (신규): dot을 공백과 같은 separator로 사용 — Logic은 항상 공백만. dot은 끝 trailing punctuation에서만 strip. mixed separator (`"1.1 1.1"`)는 입력 거부.
- **NG8** (신규): `0 0 0 0`을 valid position으로 수용 — Logic position은 항상 1-based (bar 1+, beat 1+, div 1+, tick 1+). 0은 manufacturing data로 거부.
- **NG9** (신규): Unicode digit characters (`Character.isNumber`의 모든 매칭) — `Int($0) != nil`로 ASCII digit narrow.
- **NG10** (Guardian P0-1): **Sub-bar navigation 정확도** (`goto_marker`가 `146.4.4.240` 도달) — 별도 PRD 필요. 현재 `gotoPositionViaBarSlider`는 첫 컴포넌트(bar)만 추출하여 slider에 set. parser fix는 **cache 정확성 보장까지**가 scope. 사용자 직면 영향: `goto_marker`가 cache의 bar로 navigate (4.4.240은 무시) — 이는 **현재 동작 그대로**이며 v3.1.11 회귀 0. v3.2 PRD에서 beat/div/tick slider 확장으로 sub-bar 지원 예정.

- **NG11** (Boomer P1-1): **Lenient 1-3 components 정책 폐기**. 정확히 4 components (bar/beat/div/tick)만 valid. 이유:
  - Logic UI는 모든 관찰된 빌드에서 항상 4 components 노출.
  - 1-3 components는 어떤 빌드에서도 미관찰 — 가설적 호환.
  - 위험: 미래 빌드가 tempo/BPM 등 비-position 숫자 셀을 marker list table에 노출 시 (`"120"` → `"120"` 1-component 수용) silently 잘못된 bar 120으로 navigate. nil signal 없어 caller fallback 미작동.
  - 11 원칙 "오버엔지니어링 금지" + "0.1% 엣지케이스 0"과 정합 — 가설적 호환을 위해 실제 위험 감수는 비합리적.
  - 기존 test `"17 2"` → `"17.2"` 케이스를 `_invalid`로 이동 (회귀 정직 명시).

---

## 3. User Stories & Acceptance Criteria

### US-1: 비-bar-aligned 마커 position이 cache에 정확

**As a** `logic://markers` 호출자, **I want** 모든 마커가 Logic UI 표시와 정확히 일치하는 `position` 문자열로 cache에 저장되어, **so that** consumer가 grid analysis / labelling / 외부 navigation 자동화에 거짓 데이터를 사용하지 않는다.

**AC:**
- [ ] **AC-1.1**: `"146 4 4 240."` → `"146.4.4.240"` (이번 fix 핵심).
- [ ] **AC-1.2**: `"1 1 1 1"` → `"1.1.1.1"` (한글 회귀).
- [ ] **AC-1.3**: `"17 2 3 4"` → `"17.2.3.4"`.
- [ ] **AC-1.4** (라이브): 영문 12.2에서 비-bar-aligned 마커 1개 이상 포함 프로젝트의 `logic://markers` 응답 모든 position이 UI 표시와 정확 일치.
- [ ] **AC-1.5** (parser scope only): cache에 저장된 marker.position이 정확. **navigation 정확도는 별도 — sub-bar는 NG10으로 분리**.

### US-2: 거짓 데이터 차단 (1-based / Unicode / mixed separator)

**As a** 호출자, **I want** parser가 ambiguous / non-Logic 입력을 거짓 데이터로 manufacturing하지 않고 nil 반환하여, **so that** 호출자의 fallback (`\(index+1).1.1.1`)이 안전하게 적용된다.

**AC:**
- [ ] **AC-2.1**: `""` / `"   "` / `"."` → nil
- [ ] **AC-2.2**: `"abc"` / `"1 abc"` / `"1 2 3 x"` → nil
- [ ] **AC-2.3**: `"1 2 3 4 5"` / `"1 2 3 4 5 6"` → nil
- [ ] **AC-2.4** (Guardian P0-2): `"0 0 0 0"` / `"0 1 1 1"` / `"1 0 1 1"` → nil (1-based 위반 거부)
- [ ] **AC-2.5** (Guardian P2-2): `"١٤٦ ٤ ٤ ٢٤٠"` → nil (Arabic-Indic 미지원, ASCII narrow)
- [ ] **AC-2.6** (Guardian P0-3): `"1.1 1.1"` → nil (mixed separator 거부)
- [ ] **AC-2.7**: 호출자 회귀 — parser nil 시 `enumerateMarkersFromListWindow`가 `\(index+1).1.1.1` fallback 적용.

### US-3: 영문 Logic 12.2 사용자 메뉴 경로 발견 즉시

**As a** 영문 12.2 사용자, **I want** TROUBLESHOOTING에서 정확한 메뉴 경로를, **so that** Marker List를 못 찾아 디버깅에 시간 낭비하지 않는다.

**AC:**
- [ ] **AC-3.1** (Boomer P1-2 — 13 locales): TROUBLESHOOTING.md `logic://markers` 섹션에 명시:
  - 모든 빌드 공통: **Navigate / 탐색 메뉴** 하위 (Window 메뉴 아님).
  - 코드는 13 locales 지원 — KR/EN/JA/FR/DE/ES/IT/ZH-S/ZH-T/RU/PT/NL.
  - 사용자가 본인 locale의 메뉴를 못 찾으면 `Navigate` 영문 명칭 또는 system Region을 일시적으로 영문으로 전환 후 재확인.
  - Window 메뉴에 marker list 항목 없음 — 영문 12.2 reporter 확인.
- [ ] **AC-3.2**: README Status에 v3.1.11 entry — F1+F2 짧은 요약.

### US-4: 11가지 원칙 100% 준수 (측정 가능)

**As a** maintainer, **I want** 신규/수정 코드가 사용자 11 원칙을 측정 가능한 방식으로 충족, **so that** 주니어도 즉시 이해 + 미래 회귀 0.

**AC (Guardian P1-1 응답):**
- [ ] **AC-4.1**: 신규/수정 코드의 모든 주석 한글 (영문 식별자 자체는 그대로).
- [ ] **AC-4.2**: `git grep -E '(TODO|FIXME|XXX)' Sources/` 신규 0건.
- [ ] **AC-4.3**: parser 함수 단일 책임 — string-to-canonical-position 변환만.
- [ ] **AC-4.4**: `swift build -c release` 0 warnings (SwiftLint 미사용).
- [ ] **AC-4.5**: parser API signature 변경 0 (`static func parseMarkerListPosition(_ raw: String) -> String?`).
- [ ] **AC-4.6**: parser 본문 ≤ 20 lines (doc comment 제외; `func` 시그니처부터 최종 `}` 까지).
- [ ] **AC-4.7**: SOLID/SRP — parser는 호출자에 대한 의존 0 (pure function).

---

## 4. Technical Design

### 4.1 Architecture Overview

영향 모듈 1개: `Sources/LogicProMCP/Accessibility/AXLogicProElements.swift::parseMarkerListPosition`. 호출 사이트 1곳: 같은 파일의 `enumerateMarkersFromListWindow:798`. API signature 불변.

### 4.2 Data Model Changes
없음.

### 4.3 API Design (변경 없음)
```swift
static func parseMarkerListPosition(_ raw: String) -> String?
```

### 4.4 Implementation (Apple-level, ≤ 20 lines, 한글 주석)

```swift
/// Logic Marker List 셀의 위치 문자열을 표준 "bar.beat.div.tick" 형태로 변환한다.
///
/// 관찰된 입력 변형:
/// - 한글 12.2: "1 1 1 1" (공백 구분, whole-bar)
/// - 영문 12.2: "146 4 4 240." (공백 구분 + UI 끝 마침표)
///
/// 정확히 4 컴포넌트, 각 ASCII 정수 1 이상이어야 한다. Logic UI는 항상 4
/// 컴포넌트를 노출하므로 1-3 컴포넌트는 비-position 셀(예: tempo)일 가능성
/// 으로 nil 반환한다. 호출자는 `\(index+1).1.1.1` fallback을 사용한다.
static func parseMarkerListPosition(_ raw: String) -> String? {
    // 끝의 마침표/콤마는 Logic UI rendering artifact — 반복 strip.
    var trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    while let last = trimmed.last, last == "." || last == "," {
        trimmed.removeLast()
    }
    // 공백/탭만 separator (Logic은 공백만 사용; 점은 끝에서만 의미).
    let parts = trimmed.split(whereSeparator: \.isWhitespace).map(String.init)
    // 정확히 4 컴포넌트 + ASCII 정수 + 1-based.
    guard parts.count == 4,
          parts.allSatisfy({ Int($0).map { $0 >= 1 } == true }) else {
        return nil
    }
    return parts.joined(separator: ".")
}
```

**라인 수**: 본문 13 (시그니처 + body + `}`). doc 7 + 본문 13 = 총 20.

**핵심 변경 vs v3.1.10**:
1. **trailing punctuation strip** (while-loop): `.`, `,` 끝에서만 제거 — Logic UI artifact 흡수.
2. **공백/탭만 separator**: dot 미포함 — NG7 mixed separator 거부.
3. **`Int($0)`**: ASCII digit + 1-based 동시 검증 — NG8/NG9 동시 만족.
4. **정확 4 컴포넌트** (NG11 Boomer P1-1): lenient 폐기. tempo/BPM 같은 비-position 셀이 미래 빌드에 노출되어도 silently 매뉴팩처링 안 함.
5. **`!$0.isEmpty` 가드 제거**: Swift `split` default `omittingEmptySubsequences: true`.

### 4.5 Key Technical Decisions

| Decision | Options | Chosen | Rationale |
|----------|---------|--------|-----------|
| Trailing punctuation | (a) 무시 / (b) 끝에서만 strip / (c) 모두 strip | **(b)** | (a)는 v3.1.10 버그. (c)는 ambiguous (`1.0` 같은 dec 위험). (b)는 UI artifact만 정확히 제거. |
| Separator | 공백+점 / 공백만 | **공백만** (NG7) | Logic 12.x 모든 빌드는 공백 separator. 점 추가는 Guardian P0-3에서 manufacturing 위험 (`"1.1 1.1"` → 거짓 `"1.1.1.1"`). |
| 0 component | 허용 / 거부 | **거부** (NG8) | Logic 1-based. `"0 0 0 0"` 수용은 거짓 데이터. |
| Unicode digit | `Character.isNumber` / ASCII narrow | **`Int($0)`** (NG9) | `Int(_: String)` failable initializer는 ASCII 0-9만 — 정확 + 컴팩트. |
| Component count | 엄격 4 / lenient 1-4 | **엄격 4 only** (NG11) | Boomer P1-1: lenient는 미관찰 가설 호환을 위해 실제 manufacturing 위험 감수 — 비합리적. Logic UI는 항상 4. |
| Sub-bar navigation 정확 | 본 PRD 포함 / 분리 | **분리 NG10** | `gotoPositionViaBarSlider`가 bar만 추출 — parser fix만으로 도달 불가. v3.2 PRD scope. |

---

## 5. Edge Cases (15 cases — Strategist 권고로 25 → 15 축소)

### 유효 입력 (parser → canonical)
| # | 입력 | 출력 | Severity | 출처 |
|---|------|------|----------|------|
| E1 | `"1 1 1 1"` | `"1.1.1.1"` | P0 회귀 | 한글 12.2 (existing) |
| E2 | `"146 4 4 240"` | `"146.4.4.240"` | P0 핵심 | 영문 12.2 정상 |
| **E3** | `"146 4 4 240."` | `"146.4.4.240"` | **P0 fix** | 영문 12.2 reporter 관찰 |
| E4 | `"146 4 4 240,"` | `"146.4.4.240"` | P1 방어 | 끝 콤마 |
| E5 | `"  146 4 4 240  "` | `"146.4.4.240"` | P2 | 양쪽 공백 |
| E6 | `"146  4  4  240"` | `"146.4.4.240"` | P2 | 다중 공백 (Swift split default 흡수) |
| E7 | `"146\t4\t4\t240"` | `"146.4.4.240"` | P3 | 탭 (`isWhitespace`) |
| E8 | `"17 2 3 4"` | `"17.2.3.4"` | P0 | existing valid (정확 4) |

### 무효 입력 (parser → nil)
| # | 입력 | Severity | 사유 |
|---|------|----------|------|
| E9 | `""` / `"   "` / `"."` | P1 | empty / 의미 없음 (existing 일부) |
| E10 | `"abc"` / `"1 abc"` / `"1 2 3 x"` | P1 | 비숫자 |
| **E11** | `"1"` / `"17 2"` / `"1 2 3"` | **P0** | NG11 strict 4 only (Boomer P1-1) |
| E12 | `"1 2 3 4 5"` / `"1 2 3 4 5 6"` | P1 | 5+ components (existing) |
| **E13** | `"0 0 0 0"` / `"0 1 1 1"` / `"1 0 1 1"` | **P0** | NG8 1-based 위반 (Guardian P0-2) |
| **E14** | `"١٤٦ ٤ ٤ ٢٤٠"` | **P0** | NG9 ASCII narrow (Guardian P2-2) |
| **E15** | `"1.1 1.1"` / `"146.4 4 240"` | **P0** | NG7 mixed separator (Guardian P0-3) |

총 14 edge cases (E1-E14, **단 E11이 NG11 strict로 강화되어 기존 v3.1.10 valid 케이스 1개가 invalid로 이동** — 정직 명시).

### 호출자 회귀
- **E16**: `enumerateMarkersFromListWindow`가 parser nil 받으면 `\(index+1).1.1.1` fallback 적용 (existing 회귀 보호). 통합 테스트 1개.

### Behavior change (v3.1.10 → v3.1.11)
v3.1.10 valid → v3.1.11 invalid:
- `"17 2"` (2-component lenient) — 이제 nil. tempo/BPM 비-position 셀 manufacturing 차단. 호출자는 `\(index+1).1.1.1` fallback. **release notes에 명시**.

---

## 6. Security & Permissions

### 6.1/6.2: N/A (순수 string transformation, file/process access 없음)

### 6.3 Data Protection

**Untrusted input**: parser는 사용자 본인 Logic 프로세스의 AX subtree에서 받음. attacker-controlled 아님. 그러나 방어:
- **무한 루프**: `while let last` strip은 매 iteration 1 char 감소 → O(n) 종료 보장.
- **메모리**: AXDescription 일반 < 100 chars — cap 불필요.
- **regex DoS**: regex 미사용 — `Foundation.String.split` + `Int(_:)` initializer만. ReDoS 면역.
- **Unicode digit attack** (Guardian P2-2): `Int(_: String)` failable initializer는 ASCII 0-9만 수용 → Arabic-Indic 등 자동 거부 (NG9).

---

## 7. Performance & Monitoring

| Metric | Target | Measurement |
|--------|--------|-------------|
| Parser latency | < 1µs (~50 char) | 마이크로벤치 (선택) |
| `enumerateMarkers` end-to-end (30 markers) | < 50ms | 기존 perf bench 회귀 |
| 메모리 추가 allocation | 0 (String split lazy view) | 코드리뷰 |

### 7.1 Logging
parser silent — nil 반환만. 호출자가 fallback 적용. 별도 warn 로그 불필요.

---

## 8. Testing Strategy

### 8.1 Unit Tests (parser 매트릭스 — Swift Testing parameterized)

`Tests/LogicProMCPTests/AXMarkers12MarkerListTests.swift` 확장:

```swift
@Test("parseMarkerListPosition: 유효 입력 → canonical", arguments: [
    ("1 1 1 1", "1.1.1.1"),
    ("146 4 4 240", "146.4.4.240"),
    ("146 4 4 240.", "146.4.4.240"),    // 영문 fix 핵심
    ("146 4 4 240,", "146.4.4.240"),
    ("  146 4 4 240  ", "146.4.4.240"),
    ("146  4  4  240", "146.4.4.240"),
    ("146\t4\t4\t240", "146.4.4.240"),
    ("17 2 3 4", "17.2.3.4"),
])
func parseMarkerListPosition_valid(input: String, expected: String) {
    #expect(AXLogicProElements.parseMarkerListPosition(input) == expected)
}

@Test("parseMarkerListPosition: 무효 입력 → nil", arguments: [
    "", "   ", ".",
    "abc", "1 abc", "1 2 3 x",
    "1", "17 2", "1 2 3",                              // NG11 strict 4 (1-3 components)
    "1 2 3 4 5", "1 2 3 4 5 6",                        // 5+ components
    "0 0 0 0", "0 1 1 1", "1 0 1 1",                   // NG8 1-based
    "١٤٦ ٤ ٤ ٢٤٠",                                     // NG9 ASCII narrow
    "1.1 1.1", "146.4 4 240",                          // NG7 mixed separator
])
func parseMarkerListPosition_invalid(input: String) {
    #expect(AXLogicProElements.parseMarkerListPosition(input) == nil)
}
```

총 8 + 17 = 25 cases, 단 2개 `@Test`. Swift Testing parameterized 패턴 (skill: swift-testing-pro).

### 8.2 Integration Tests

`AXMarkers12MarkerListTests.swift`에 **신규 통합 1개**:
- 비-bar-aligned 마커 (raw `"146 4 4 240."`)가 `enumerateMarkersFromListWindow`를 통해 `MarkerState.position == "146.4.4.240"`으로 surface — synthetic AX tree fixture로 검증.

기존 통합 테스트 (`enumerateMarkers_unparseablePosition_usesIndexFallback`): nil 시 `\(index+1).1.1.1` fallback 회귀 보호 (E16) — 변경 없이 PASS 유지.

### 8.3 Live E2E (Logic Pro 12.2)

**Phase F 또는 Phase G에서 실행**. 단계 (Strategist 정정 + Guardian P1-2 안전 절차):

1. **언어 전환 (영문 빌드 검증 시 only)**:
   - 안전한 방식: System Settings → Language & Region → Logic Pro 항목에서 per-app preferred language를 English로. Logic restart.
   - **금지**: `defaults write -g AppleLanguages` 시스템 전역 변경. 또는 우/좌 키 토글 (Logic 12.2에 없음).
   - 검증 후 same path로 복구 (Korean).
2. 신규 프로젝트 생성 + 비-bar-aligned 마커 1개 (예: bar 5 beat 2 div 3 tick 100) 추가.
3. v3.1.11 binary로 stdio JSON-RPC `resources/read logic://markers` 호출.
4. 응답에서 비-bar-aligned 마커의 position이 정확 (`"5.2.3.100"`) 검증.
5. (선택) `goto_marker { name }` 호출 — verified=true이지만 sub-bar 무시 (NG10) 명시적 확인 — 즉 cache는 정확하나 navigation은 bar만.

`docs/live-verify-v3.1.11.md` 신규 작성. Tier 1 (auto), Tier 2 (live), Tier 3 (NG/honest disclosure).

### 8.4 Regression
1062 → 1075+ PASS. Existing parser tests 변경 없음 — 신규 추가만.

---

## 9. Rollout Plan

### 9.1 Migration
없음 — parser 동작 정정.

### 9.2 Feature Flag
없음. 정확성 fix는 unconditional ship.

### 9.3 Rollback (Guardian P2-1 응답)
- `git revert <v3.1.11 fix commit> <v3.1.11 test commit>` 2-commit 범위.
- parser self-contained, side-effect 0 — clean revert.
- StateCache 영향 없음 (in-memory cache는 binary restart 시 자동 리셋).

---

## 10. Dependencies & Risks

### 10.1 Dependencies
- `Foundation.String.split(whereSeparator:)` — 안정.
- `Foundation.Int(_: String)` failable initializer — 안정.
- `Foundation.Character.isWhitespace` — 안정.

### 10.2 Risks
| Risk | Probability | Impact | Mitigation |
|------|------------|--------|------------|
| Logic 12.3+에서 또 다른 변형 | Medium | Medium | parser는 trailing-strip + whitespace separator로 방어적. 새 변형 보고 시 case 추가 1줄. |
| 한글 빌드도 끝 마침표 표기 발견 | Low | None | v3.1.11 parser는 양쪽 모두 처리. |
| Sub-bar navigation 사용자 기대 (NG10) | Medium | Low | 릴리스 노트 + TROUBLESHOOTING에 명시: "v3.1.11은 cache 정확까지. navigation은 bar 수준 (v3.2 예정)." |

---

## 11. Success Metrics

| Metric | v3.1.10 | v3.1.11 | Method |
|--------|---------|---------|--------|
| 비-bar-aligned cache 정확률 | 0% | 100% | 라이브 측정 |
| Test count | 1062 | ≥ 1075 | `swift test` |
| Build warnings | 0 | 0 | `swift build -c release` |
| Issue #9 closure | OPEN | CLOSED + verified | GitHub state |
| 4-agent P0/P1 잔존 | n/a | 0 | Phase G review |
| 11 원칙 측정 가능 항목 (G6) | n/a | 100% PASS | Phase G checklist |

---

## 12. Open Questions

- [x] OQ-1: 콤마 separator? **NG2 — 보고 시 확장.**
- [x] OQ-2: parameterized tests? **Yes — `@Test(arguments:)` 컴팩트.**
- [x] OQ-3: VOCALS id 순서? **NG4 — visible-row-order 의도된 동작.**
- [x] OQ-4: 영문 외 locale? **NG5 — 보고 시 확장.**
- [x] OQ-5 (Guardian P0-1): sub-bar navigation? **NG10 — v3.2 PRD로 분리. 본 PRD는 cache 정확까지.**
- [x] OQ-6 (Guardian P0-2): zero positions? **NG8 — 거부 (1-based).**
- [x] OQ-7 (Guardian P0-3): mixed separator? **NG7 — 거부 (manufacturing 차단).**
- [x] OQ-8 (Guardian P2-2): Unicode digit? **NG9 — `Int(_:)` ASCII narrow.**

---

## 부록 A: 11 원칙 → AC 매핑

| # | 원칙 | AC | 측정 |
|---|------|-----|------|
| 1 | 실리콘밸리 0.1% | AC-4.1~7 + Phase G 4-agent | P0/P1=0 |
| 2 | Apple 수준 | §4.4 17 lines + Foundation API only | review checklist |
| 3 | 0.1% 엣지케이스 0 | E1-E16 + 통합 1 | tests PASS |
| 4 | 오버엔지니어링 금지 | NG2/5/7-10 명시; 25→15 cases | review |
| 5 | 데드코드 0 | AC-4.2 grep | shell |
| 6 | 컴팩트 | AC-4.6 ≤20 lines | wc -l |
| 7 | 표준 레퍼런스 | swift-api-design + Apple stdlib only | review |
| 8 | 주니어 가독성 | doc 한글 + step 별 의도 | review |
| 9 | 한글 주석 | AC-4.1 | grep |
| 10 | SOLID/SRP | AC-4.7 (pure function) | review |
| 11 | 컴팩트 | parameterized tests + 본문 13 lines | wc -l |

---
