# Pipeline Status: v39-hardening-and-midi-read

**PRD**: docs/prd/PRD-v39-hardening-and-midi-read.md (v0.2)
**Size**: XL
**Current Phase**: 5 (TDD 개발 — PR-1부터 순차)
**실행 모델**: 코드 100% codex gpt-5.5 xhigh / 오케스트레이터는 판단·문서·리뷰만 / 리뷰 게이트 boomer(codex xhigh)

## Tickets

| Ticket | Title | Status | Review | Notes |
|--------|-------|--------|--------|-------|
| T1 | 릴리스 무결성 팩 (PR-1) | Todo | - | |
| T2 | HC 전역화 마감 (PR-2) | Todo | - | BREAKING |
| T3 | 소형 수정 팩 (PR-3) | Todo | - | |
| T4 | MCP 프로토콜 팩 (PR-4) | Todo | - | SDK 0.12.1 확인됨 |
| T5a | SMFReader + Export 임시파일 (PR-5) | In Review | - | 순수 유닛 (T5 분할), 파서 boomer 정독 중 |
| T5b | MIDI 읽기 표면 (PR-5) | **Deferred** | - | **T0 라이브 게이트 FAIL** — export 저장 패널 하드 월(docs/spikes/midi-export-t0-evidence.md). 신규 공개 커맨드 없음 |
| T6 | Channel EQ registry + rename_marker 스파이크 (PR-6) | Todo | - | 라이브 census 게이트 |
| D-1 | applyback 브랜치 처분 | **Done** | - | 델타 0 (PR #24 기머지), origin+로컬 삭제 2026-07-06 |

## Review History

| Phase | Round | Verdict | P0 | P1 | P2 | Notes |
|-------|-------|---------|----|----|-----|-------|
| 2 | 1 | REQUEST CHANGES | 0 | 7 | 5 | 전건 수용 → PRD v0.2 |
| 2 | 2 | REQUEST CHANGES | 0 | 0 | 1 | #10 잔여(Risks 표 1행) → 수정, 검증은 Phase4 r2에 통합(r3 stdin 행으로 중단) |
| 4 | 1 | REQUEST CHANGES | 0 | 3 | 2 | T5 분할(T5a/T5b), mmc_locate carve-out, TestTransport 하니스, 열거 소스, set_autopunch 제거 — 전건 수용 |
| 4 | 2 | **PASS** | 0 | 0 | 0 | 6/6 RESOLVED (PRD 잔여 포함) — Phase 2+4 수렴 완료 |

## 머지 순서
PR-1 → PR-2 → PR-3 → PR-4 → PR-5 → PR-6 (각각 CI green 후 순차 머지, 라이브 게이트 실패 시 해당 PR honest defer)
