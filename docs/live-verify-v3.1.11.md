# Live Verification Runbook — v3.1.11 (Issue #9)

**검증 시점**: v3.1.11 release 직전 + 사용자 보고 시 재현용.
**대상 fix**: `parseMarkerListPosition` strict 4 + trailing punctuation strip + 1-based + ASCII narrow + mixed separator reject.
**대상 doc**: TROUBLESHOOTING.md 13 locales 메뉴 경로.

---

## Tier 1 — Automated (CI / dev box)

```bash
swift test --no-parallel
# → 1064 / 1064 PASS

swift build -c release
# → 0 warnings

swift test --no-parallel --filter parseMarkerListPosition
# → 2 functions (parameterized 25 cases) ALL PASS

swift test --no-parallel --filter testServerVersionMatchesPackagingArtefacts
# → version 3.1.11 모든 artifact 동기 검증

brew test logic-pro-mcp  # 설치 후
# → exit 0
```

추가 verification (사용자 11 원칙 측정 가능 항목):

```bash
# AC-4.2: TODO/FIXME/XXX 신규 0건
git diff main..HEAD -- Sources/ | grep -E '^\+.*\b(TODO|FIXME|XXX)\b'
# → 0 lines (예상)

# AC-4.6: parser 본문 ≤ 20 lines
awk '/static func parseMarkerListPosition/,/^    \}$/' \
  Sources/LogicProMCP/Accessibility/AXLogicProElements.swift | wc -l
# → 15 lines (시그니처 + body + closing brace)
```

---

## Tier 2 — Live (Logic Pro 12.2 실기기)

### 2.1 영문 12.2 비-bar-aligned 마커 회귀 (F2 fix 검증)

**언어 전환 (per-app, 안전)**:
1. System Settings → Language & Region → Apps → Logic Pro → English (영문) 선택
2. Logic Pro 종료 + 재실행

**시나리오**:
1. 신규 프로젝트 생성 (BPM 120, 4/4)
2. `Navigate → Open Marker List` (Window 메뉴 아님 — 영문 12.2 확인)
3. 마커 1개 생성 후 비-bar-aligned 위치 (예: bar 5 beat 2 div 3 tick 100)로 이동
   - Marker List 윈도우 → 해당 row → Position 셀 → 직접 입력 또는 마커 위치를 수동 조정
4. v3.1.11 binary로 stdio JSON-RPC 호출:
   ```bash
   echo '{"jsonrpc":"2.0","id":1,"method":"resources/read","params":{"uri":"logic://markers"}}' \
     | LogicProMCP
   ```
5. **기대 응답**: position이 `"5.2.3.100"` (정확). v3.1.10이라면 fallback `"1.1.1.1"`.

**복구 절차**: System Settings → Language & Region → Apps → Logic Pro → Korean(한국어). Logic 재시작. 만약 Logic Pro가 Apps 리스트에 안 보이면 + 버튼 → Logic Pro 추가 → Korean 선택.

### 2.2 한글 12.2 whole-bar 회귀 (G3 양쪽 보장)

**시나리오**: 한글 빌드에서 일반 whole-bar 마커 생성. 응답 position == `"1.1.1.1"` (canonical). T2 unit 통과 + T3 통합 회귀.

### 2.3 13 locales 메뉴 경로 (F1 doc 검증)

위 2.1과 같은 절차에서 `Navigate → Open Marker List` (영문 빌드) 동작 확인.
한글 빌드에서 `탐색 → 마커 목록 열기` 동작 확인.
**Window 메뉴에 marker 항목 없음** — 영문 reporter 보고 일치.

### 2.4 Behavior change (`"17 2"` invalid 이동) 회귀

```bash
# 1-3 component 입력은 v3.1.11에서 fallback (silently 잘못된 bar 안 가도록)
# unit test로 보장; 라이브 검증은 reporter 시나리오 의존
```

라이브에서 직접 시뮬레이션 어려움 (Logic UI는 정상 4 컴포넌트만 노출). T2 invalid matrix가 보장.

---

## Tier 3 — NG / Honest Disclosure

| NG | 내용 |
|----|------|
| **NG10** | **Sub-bar navigation** 불가. `goto_marker { name: "VOCALS" }`가 cache의 정확한 `"146.4.4.240"` 보지만 AX `gotoPositionViaBarSlider`는 첫 컴포넌트만 추출 → bar 146으로만 이동. v3.2 별도 PRD에서 해결 예정. |
| **NG11** | **Lenient 1-3 components 폐기**. 어떤 Logic 빌드도 1-3 컴포넌트를 사용하지 않음. 미래 빌드가 헤더 행 단축 표기 노출 시 → fallback `\(index+1).1.1.1` (silently manufacturing 안 함 — honest). |
| NG7 | dot은 끝 punctuation에서만 의미. mixed separator (`"1.1 1.1"`)는 거부. |
| NG8 | 1-based 검증. `"0 0 0 0"` 거부 (manufacturing 차단). |
| NG9 | ASCII digit 0-9만 수용 (Arabic-Indic 등 비-ASCII 거부). |

### 미검증 항목 (사용자 보고 시 재방문)

- Logic Pro 12.3+ — 미공개. AX 표기 변형 시 추가 case 필요.
- Logic Pro 11.x — 본 프로젝트가 12.x primary target. 11.x AX rule 미검증.
- KR/EN 외 11 locales — 코드는 13 locales 모두 지원하나, 라이브 실기기 검증은 KR/EN만.

---

## When to update this runbook

- `parseMarkerListPosition` 변경 시 Tier 1의 unit count + Tier 2 시나리오 갱신
- 새 Logic 버전 출시 시 Tier 2 전체 재실행
- 새 locale 보고 시 Tier 2.3 표 행 추가
