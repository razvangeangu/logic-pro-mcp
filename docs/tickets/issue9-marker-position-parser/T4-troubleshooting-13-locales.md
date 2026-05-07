# T4: TROUBLESHOOTING 13 locales + Window 메뉴 부재 명시

**PRD Ref**: PRD-issue9 > AC-3.1 (Boomer P1-2)
**Priority**: P1
**Size**: S (< 30min)
**Status**: Todo
**Depends On**: None (병렬 가능)

---

## 1. Objective
영문 12.2 reporter가 Window 메뉴를 검색하다 발견했던 discoverability 결함을 모든 locale 사용자가 다시 겪지 않도록 docs/TROUBLESHOOTING.md에 명시.

## 2. Acceptance Criteria
- [ ] AC-1: TROUBLESHOOTING.md `logic://markers always returns empty` 섹션의 "Fix:" 부분이 다음을 포함:
  - **모든 빌드 공통**: Marker List 윈도우는 **Navigate / 탐색** 메뉴 하위 (Window 메뉴 아님).
  - 13 locales 모두 동일 메뉴 위치 (영문 명칭만 변경).
  - Window 메뉴에 marker 항목 없음 — 영문 reporter 확인.
- [ ] AC-2: README의 v3.1.9 / v3.1.10 status entry는 그대로. v3.1.11 항목 추가 (T5에서).
- [ ] AC-3: 한글 작성 (코드 외 자연어).

## 3. Implementation

### 3.1 Files to Modify
| File | Change |
|------|--------|
| `docs/TROUBLESHOOTING.md` | `logic://markers` 섹션 "Fix" 부분 확장 |

### 3.2 Diff sketch

기존:
```markdown
**Fix:** open the Marker List window once via `탐색 → 마커 목록 열기` (KR) / `Navigate → Open Marker List` (EN). 후 ~3-15 seconds the next poll cycle picks up the markers.
```

변경:
```markdown
**Fix**: Marker List 윈도우는 **Navigate / 탐색** 메뉴 하위에 있습니다 (Window 메뉴 아님 — `thomas-doesburg`의 Issue #9 보고로 확인된 영문 12.2 동작).

| UI Locale | 메뉴 경로 |
|-----------|-----------|
| 한글 | `탐색 → 마커 목록 열기` |
| 영문 | `Navigate → Open Marker List` |
| 일본어 / 프랑스어 / 독일어 / 스페인어 / 이탈리아어 / 중국어(간/번체) / 러시아어 / 포르투갈어 / 네덜란드어 | 동일 메뉴 위치, 영문 명칭만 번역 — 본인 locale의 Navigate 항목 하위 확인 |

코드는 13 locales의 Marker List 윈도우 타이틀을 인식 (`AXLogicProElements.markerListWindowSuffixes`). 메뉴 명칭이 본인 locale에서 명확하지 않다면 System Settings → Language & Region에서 Logic Pro만 임시로 영문으로 전환 후 재확인 가능.

윈도우를 한 번 열고 ~3-15초 후 다음 poll cycle에서 마커가 cache로 surface됩니다.
```

## 4. Review Checklist
- [x] Boomer P1-2 13 locales 통합
- [x] Window 메뉴 부재 명시
- [x] System-wide language switch 위험 회피 (per-app 권장)
- [x] 한글 (자연어)
