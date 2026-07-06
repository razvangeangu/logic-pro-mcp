# T1: 릴리스 무결성 팩 (PR-1)

**PRD Ref**: PRD-v39-hardening-and-midi-read > US-1
**Priority**: P1
**Size**: M
**Status**: Todo
**Depends On**: None
**Branch**: feat/v39-release-integrity

---

## 1. Objective
tag-push 릴리스·release.sh·CI가 테스트/브랜치/lockfile/버전 표면을 fail-closed로 게이트하고, `versionReleaseTimestamp`를 CHANGELOG SSOT에 결박한다.

## 2. Acceptance Criteria
- [ ] AC-1: `.github/workflows/release.yml` build job — Select Xcode 이후, 패키징/코드사인 **이전**에 `swift test --no-parallel` 스텝 추가 (CoreMIDI -50 skip은 기존 테스트가 처리)
- [ ] AC-2: `Scripts/release.sh` — tag push/GH release 이전에 (a) `git branch --show-current == main` + `HEAD == origin/main` 게이트(release-stable.sh:53,66 미러), (b) `swift test --no-parallel`, (c) `git diff --exit-code Package.resolved` 실행. 실패 시 즉시 종료
- [ ] AC-3: `.github/workflows/ci.yml` — 빌드 후 `git diff --exit-code Package.resolved` 스텝 (drift 시 fail)
- [ ] AC-4: `ResourceProvider.versionReleaseTimestamp` stale 값(2026-06-23) → CHANGELOG 최신 릴리스(3.8.0, 2026-07-05 UTC)로 수정
- [ ] AC-5: VersionConsistencyTests 확장 — (a) 리소스가 노출하는 lastModified annotation 날짜 == CHANGELOG 최신 릴리스 헤딩 UTC 날짜(테스트가 CHANGELOG.md 파싱), (b) README의 버전 참조가 `ServerConfig.serverVersion`과 일치. private static 직접 비교 금지 — 공개 annotation 경유
- [ ] AC-6: 기존 release/tag 흐름의 다른 스텝 무변경

## 3. TDD Spec (Red Phase)

| # | Test Name | Type | Expected (Red 시점) |
|---|-----------|------|--------------------|
| 1 | `versionReleaseTimestamp_matches_latest_changelog_release_date` | Unit | FAIL (현재 2026-06-23 ≠ 2026-07-05) |
| 2 | `readme_version_references_match_server_version` | Unit | 현재 상태 따라 — stale이면 FAIL, 아니면 구현 후 회귀 가드 |
| 3 | `release_script_contains_main_branch_and_test_gates` | Contract | FAIL (release.sh에 게이트 없음) — InstallScriptContractTests 스타일로 스크립트 내용 검증 |
| 4 | `release_workflow_runs_tests_before_packaging` | Contract | FAIL — release.yml 내용에서 test 스텝이 패키징 스텝보다 앞에 있는지 검증 |
| 5 | `ci_workflow_gates_package_resolved_drift` | Contract | FAIL — ci.yml 내용 검증 |

### Test File Location
- `Tests/LogicProMCPTests/VersionConsistencyTests.swift` (확장)
- `Tests/LogicProMCPTests/ReleasePipelineContractTests.swift` (신규 — InstallScriptContractTests 패턴 복제)

### 주의
- swift-testing dead-assert 금지: `#expect(optionalBool == true)` 형태 금지, force-unwrap 지역변수 사용
- CHANGELOG 파싱: `## [X.Y.Z] — YYYY-MM-DD` 헤딩 정규식, Unreleased 섹션 제외

## 4. Implementation Guide

| File | Change |
|------|--------|
| .github/workflows/release.yml | test 스텝 추가 (패키징 전) |
| .github/workflows/ci.yml | lockfile drift 스텝 |
| Scripts/release.sh | branch/test/lockfile 게이트 (release-stable.sh 미러) |
| Sources/LogicProMCP/Resources/ResourceProvider.swift | timestamp 2026-07-05 |
| Tests/…/VersionConsistencyTests.swift, ReleasePipelineContractTests.swift | 위 테스트 |

검증: `swift test --no-parallel` 전체 + `bash -n Scripts/release.sh` + (있으면) actionlint.

## 5. Edge Cases
- E1: CI 러너 CoreMIDI -50 — 기존 skip 경로 신뢰, release.yml 테스트 스텝도 동일
- E2: CHANGELOG에 Unreleased만 있고 릴리스 헤딩 없음 — 테스트가 명확한 메시지로 fail

## 6. Review Checklist
- [ ] Red FAILED 확인 → Green PASSED → Refactor PASSED 유지
- [ ] AC 전부 충족 / 기존 테스트 무파손 / 불필요 변경 없음
