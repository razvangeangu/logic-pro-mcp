# T9 — live-verify-v3.2.0 Runbook

**Status**: Todo
**의존성**: T0 결과 + T1-T7 통합
**Size**: S
**PRD**: AC-7.6

## 산출물

`docs/live-verify-v3.2.0.md` (3-tier runbook). 형식은 v3.1.11 의 `docs/live-verify-v3.1.11.md` 패턴 따름.

## 구조

```markdown
# Live Verification Runbook — v3.2.0 (NG10 + Provenance)

## Tier 1 — Automated
- swift test --no-parallel → 1074+ PASS
- swift build -c release → 0 warnings
- swift test --filter parseFourComponentPosition / MarkerStateCodable / gotoPosition
- testServerVersionMatchesPackagingArtefacts → 3.2.0
- brew test logic-pro-mcp

## Tier 2 — Live (Logic Pro 12.2 실기기)
### 2.1 4-component dialog 정밀 nav (NG10 fix 검증)
### 2.2 Slider partial fallback (empty project)
### 2.3 Marker provenance — `goto_marker` fallback uncertainty
### 2.4 Codable backward compat — v3.1.x snapshot decode
### 2.5 IME 시나리오 (T0 결과 영구 기록)

## Tier 3 — NG / Honest Disclosure
- NG10 closed (이 릴리스에서 닫힘)
- NG-v3.2-1: Logic 11.x 미검증
- NG-v3.2-2: SMPTE 정밀 nav는 별도 mmc.locate 필요
- NG-v3.2-3: IME OS 변경에 따라 Tier mitigation 재검증 필요할 수 있음
```

## T0 spike 결과 영구 기록 위치 (Tier 2.5)

```markdown
### 2.5 IME 시나리오 (T0 spike 영구 기록)

| 시나리오 | Logic 빌드 | IME | T0 결과 | 구현 Tier | 라이브 검증 |
|---------|------------|-----|--------|-----------|------------|
| S1 | 영문 12.2 | ABC | [PASS/FAIL — T0에서 채움] | Tier X | [재검증 PASS/FAIL] |
| S2 | 한글 12.2 | ABC | [...] | Tier X | [...] |
| S3 | 한글 12.2 | Hangul | [...] | Tier X | [...] |
```

## Acceptance Criteria

- **AC-T9.1**: `docs/live-verify-v3.2.0.md` 생성
- **AC-T9.2**: 3 Tier 구조 + Tier 2.5에 T0 결과 영구 기록
- **AC-T9.3**: NG-v3.2 honest disclosure 섹션
- **AC-T9.4**: 한글 마크다운, "When to update this runbook" 섹션 포함

## Out of Scope

- 실기기 검증 자동화 — 영구 수동
- 다른 locale (FR/DE/JA 등) 시나리오 — KR/EN만 본 runbook
