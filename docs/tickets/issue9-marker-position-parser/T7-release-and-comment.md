# T7: release v3.1.11 + Issue #9 정중 감사 답글 + 사용자 보고

**PRD Ref**: PRD-issue9 > §11
**Priority**: P0
**Size**: S (< 30min)
**Status**: Todo
**Depends On**: T1-T6

---

## 1. Objective
- `Scripts/release.sh v3.1.11` 실행 — 모든 artifact 게시.
- Issue #9에 thomas-doesburg에게 정중하고 존중의 의미를 담은 감사 답글.
- 사용자(Isaac)에게 최종 보고.

## 2. Acceptance Criteria
- [ ] AC-1: `bash Scripts/release.sh v3.1.11` 0 error → tag v3.1.11 + GitHub release 게시.
- [ ] AC-2: SHA256 검증: Formula = SHA256SUMS = downloaded tarball.
- [ ] AC-3: Issue #9 답글 — thomas-doesburg에게:
  - F1 발견에 대한 명시적 감사 (locale doc gap 해결)
  - F2 (parser bug) 정밀 보고에 대한 감사 (raw `"146 4 4 240."` 값 + UI 표시 일치 검증)
  - v3.1.10 → v3.1.11 fix 요약
  - Boomer P1-1 lenient 폐기 결정 (Issue #9의 후속 영향)
  - NG10 sub-bar 한계 정직 명시 (v3.2 예정)
  - 13 locales doc 확장
  - 시간 + 노력에 진심 어린 감사 (`thomas-doesburg`의 review가 v3.1.5/6/7 false-positive 사이클을 끊은 가치)
  - Issue close 권고
- [ ] AC-4: GitHub Issue #9 close (gh issue close).
- [ ] AC-5: 사용자(Isaac)에게 최종 한글 보고:
  - 8 phases 진행 결과
  - PRD v0.3 + 5 P0/P1 통합
  - 1062 → 1075 tests PASS
  - 라이브 e2e 결과
  - 11 원칙 measured 항목 100%
  - 후속 v3.2 (sub-bar nav) 안내

## 3. Implementation

### 3.1 Pre-release 체크
```bash
swift test --no-parallel  # 1075 / 1075 PASS
swift build -c release     # 0 warnings
git status --short         # all committed
gh issue view 9 --json state # OPEN
```

### 3.2 Release
```bash
bash Scripts/release.sh v3.1.11
```

### 3.3 Issue #9 답글
template:
```markdown
@thomas-doesburg, **v3.1.11이 방금 릴리스되었고 Issue #9를 닫습니다** — https://github.com/MongLong0214/logic-pro-mcp/releases/tag/v3.1.11

먼저 두 발견 모두에 대해 진심으로 감사드립니다.

**F1 — Window 메뉴 부재 발견**: 사용자 입장의 직관적 검색 경로(Window)가 영문 12.2에서 작동 안 했고, 결국 Navigate 메뉴 발견까지 직접 디버깅하셨습니다. 그 보고 덕분에 13개 locale (코드는 이미 지원) 모두에 대한 메뉴 경로를 docs/TROUBLESHOOTING.md에 정직하게 명시했습니다 (자세한 내용 v3.1.11 CHANGELOG).

**F2 — parser trailing-dot 버그**: VOCALS 마커의 raw `"146 4 4 240."` 값과 UI 표시 (`"146 4 4 240."`)의 정확한 비교는 단순한 버그 보고가 아니라 정밀한 diagnosis였습니다. 결과:

[표]

**Boomer 후속 발견 (Issue #9 보고가 촉발)**: parser strict 4 components 정책으로 강화 — lenient 1-3 components가 미래 Logic 빌드에서 tempo/BPM 같은 비-position 셀이 marker list 컬럼에 등장 시 silent manufacturing 위험. 이번 PRD review에서 codex BOOMER-6가 catch — Issue #9 같은 정밀한 보고가 없었으면 발견 안 됐을 것입니다.

**Sub-bar navigation (NG10, 정직)**: `goto_marker { name }`가 cache의 정확한 position을 surface하지만, AX `gotoPositionViaBarSlider`는 첫 컴포넌트만 추출 — sub-bar 정확도 navigation은 v3.2 별도 PRD (`gotoPositionViaBarSlider` 확장 필요). 이번 v3.1.11은 **cache 정확까지** scope 한정. 정직히 명시.

**Test count**: 1062 → 1075 PASS. parameterized `@Test(arguments:)` 패턴으로 25 edge cases 컴팩트.

**Process**: 11 원칙 (실리콘밸리 0.1% / Apple 수준 / 0 데드코드 / 한글 주석 / SOLID / 컴팩트) 4-agent review 통합 후 ship. PRD/티켓/runbook 모두 영구 보존 (`docs/prd/`, `docs/tickets/issue9-...`, `docs/live-verify-v3.1.11.md`).

다시 한 번 진심으로 감사드립니다. Issue #7→#8→#9 사이클이 이 codebase의 신뢰성을 quantum leap 시켰습니다. 빠르고 정확한 보고 덕분입니다.

이번 fix 후 또 다른 12.x 결함을 발견하시면 언제든 follow-up 환영합니다.

— closed in v3.1.11
```

### 3.4 사용자 보고
보고 form은 PRD §11 success metrics 표 + 8 phases 진행 + 후속 안내.

## 4. Review Checklist
- [x] thomas-doesburg에 진심 어린 감사 (boomer P1-1 lenient 발견을 issue #9가 촉발했음 인정)
- [x] NG10 정직 명시
- [x] release artifact 무결성 검증
- [x] 사용자 보고 11 원칙 매핑
