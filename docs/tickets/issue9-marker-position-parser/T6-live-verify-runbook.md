# T6: live-verify-v3.1.11.md (3-tier runbook)

**PRD Ref**: PRD-issue9 > §8.3
**Priority**: P2
**Size**: S (< 30min)
**Status**: Todo
**Depends On**: T1-T5

---

## 1. Objective
영구 보존 검증 절차 — 미래 maintainer가 v3.2 또는 새 Logic 버전 대응 시 동일 검증 매트릭스 재현 가능.

## 2. Acceptance Criteria
- [ ] AC-1: `docs/live-verify-v3.1.11.md` 신규 — Tier 1 (auto), Tier 2 (live), Tier 3 (NG / honest disclosure).
- [ ] AC-2: 라이브 e2e 절차에 per-app language switch 안전 절차 (System Settings 경로) 명시 — system-wide `defaults write` 금지.
- [ ] AC-3: 비-bar-aligned 마커 생성 절차 + 검증 명령 + 기대 응답.
- [ ] AC-4: NG10 sub-bar navigation 한계 명시 — 사용자가 v3.2 대기 안내.

## 3. Implementation

### 3.1 Files
| File | Change |
|------|--------|
| `docs/live-verify-v3.1.11.md` | 신규 작성 |

### 3.2 Outline

```markdown
# Live Verification — v3.1.11 (Issue #9)

## Tier 1: Automated
- swift test --no-parallel → 1075 PASS
- swift build -c release → 0 warnings
- brew test logic-pro-mcp → exit 0
- testServerVersionMatchesPackagingArtefacts → PASS

## Tier 2: Live (Logic Pro 12.2)
### 2.1 Trailing-dot position (영문 12.2)
- 언어 전환 (per-app, 안전): System Settings → Language & Region → Apps → Logic Pro → English
- Logic restart
- 신규 프로젝트 + 비-bar-aligned 마커 1개 (`Navigate → 마커 생성`, playhead at bar 5 beat 2 div 3 tick 100)
- `logic://markers` 응답 검증: position == `"5.2.3.100"`
- Logic 종료 → System Settings → Logic Pro → Korean 복구

### 2.2 Lenient 폐기 회귀
- 동일 프로젝트에서 (가설) 헤더 행 단축 표기가 발생해도 silent 잘못된 bar 안 가도록 — fallback 적용 검증

### 2.3 13 locale 메뉴 경로
- 영문 빌드에서 `Navigate → Open Marker List` 동작 확인 (Window 메뉴 부재 확인)

## Tier 3: NG / Honest Disclosure
- NG10 sub-bar navigation: cache는 정확하나 navigate는 bar 수준 (v3.2 PRD 예정)
- NG11 lenient 폐기: behavior change 정직 명시
- NG5 (구) → 폐기 — 13 locales 모두 doc 커버
```

## 4. Review Checklist
- [x] 안전한 language switch 절차
- [x] NG 명시
- [x] 미래 Logic 버전 재현 가능
