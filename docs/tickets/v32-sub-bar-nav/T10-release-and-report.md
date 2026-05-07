# T10 — Release v3.2.0 + Final Report

**Status**: Todo
**의존성**: T1-T9 모두 완료 + Phase G 최종 review ALL PASS
**Size**: S
**PRD**: §10 success metrics

## 절차

1. `git status` clean 확인
2. `swift test --no-parallel` → 1074+ PASS
3. `swift build -c release` → 0 warnings
4. **Phase G 최종 4-agent review (boomer + strategist + guardian + tester)** ALL PASS
5. `bash Scripts/release.sh v3.2.0`
6. SHA 3-way 무결성 검증:
   - Formula sha256
   - GH release SHA256SUMS.txt
   - 다운로드 tarball 실제 SHA
   - 모두 일치 ✓
7. `brew uninstall logic-pro-mcp` → `brew untap` → `brew tap` (force fresh) → `brew install` → `brew test` PASS
8. `LogicProMCP --check-permissions` → granted
9. **사용자 (Isaac) 라이브 검증** Tier 2 (T9 runbook) — 영문 12.2, 한글 12.2, IME ON 3 시나리오
10. 사용자 보고 — Korean, 8-phase summary, 11 원칙 매핑, success metrics

## 사용자 보고 양식 (참고)

```markdown
# v3.2.0 완료 보고 — NG10 closed + Boomer P2-3 closed

**Release**: https://github.com/MongLong0214/logic-pro-mcp/releases/tag/v3.2.0

## 8 Phase 결과
| Phase | 결과 |
|-------|------|
| A — 코드 분석 | ✅ |
| B — PRD v0.1~v0.4 | ✅ Boomer 4-round → ALL PASS |
| C — PRD review | ✅ Boomer ALL PASS |
| D — Ticket 분해 (T0-T10) | ✅ |
| E — Ticket review | ✅ |
| F — TDD 구현 (T0 PASS 후 T1-T9) | ✅ 1074+ PASS |
| G — 최종 review | ✅ ALL PASS |
| H — Release + brew test + Tier 2 라이브 | ✅ |

## 11 원칙 매핑
[T1-T9 각 ticket의 한글 주석, AC-4.x grep 결과 등]

## 무결성 검증
- Formula sha256 = SHA256SUMS = downloaded tarball
- brew install + test PASS

## 변경 요약
- NG10 closed (sub-bar nav 정확도)
- Boomer P2-3 closed (marker provenance)
- 28+ test cases 추가
- Codable backward compat 보장

## 후속 (v3.3)
- Logic 11.x AX 표면 검증
- Timecode 정밀 nav (mmc.locate 자동 라우팅)
```

## Acceptance Criteria

- **AC-T10.1**: SHA 3-way 일치
- **AC-T10.2**: brew install + test PASS
- **AC-T10.3**: Tier 2 라이브 검증 PASS (Isaac 직접)
- **AC-T10.4**: GitHub release page에 RELEASE-METADATA.json + SHA256SUMS.txt + tarball + binary 모두 첨부
- **AC-T10.5**: 사용자 보고 작성 + Issue #9 (이미 closed) 갱신 코멘트 (NG10 closed in v3.2.0 + 링크)
- **AC-T10.6**: 메모리 갱신 — `project_v320_shipped.md` + MEMORY.md index

## Out of Scope

- v3.3 PRD 시작 — 별도 사이클
