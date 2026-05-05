# Pipeline Status: issue1-keycmd-port-routing

**PRD**: docs/prd/PRD-issue1-keycmd-port-routing.md (v0.4 Approved + Phase 4 Loop 1/2 micro-revisions)
**Size**: L
**Current Phase**: 4 (Ticket review Loop 2 → Phase 5 진입)
**Target Release**: v3.1.6 (v3.1.5는 thomas-doesburg #3/#4/#5 점유)
**GitHub Issue**: #1 (xaexx1)

## Ticket Status 정의
- **Todo**: 미착수
- **In Progress**: 구현 중
- **In Review**: 리뷰 진행 중
- **Done**: 완료 (AC 충족 + 테스트 PASS)
- **Invalidated**: 역행으로 무효화됨

## Tickets (의존성 순서)

| Ticket | Title | Status | Review | Notes |
|--------|-------|--------|--------|-------|
| T1 | HonestContract `.portUnavailable` enum + terminalErrorCodes | Todo | - | Foundation — T4/T6 의존 |
| T2 | MIDIDispatcher `validatePort` + `validateMidiChannel` helpers | Todo | - | Foundation — T5 의존 |
| T3 | NoteSequenceParser API 변경 (`Result<[ParsedNote], NoteSequenceParseError>`) | Todo | - | Foundation — T5 / play_sequence / record_sequence 의존 |
| T4 | ChannelRouter `bypassReadinessOps` + available==false `.portUnavailable` 분기 | Todo | - | Depends: T1 |
| T5 | MIDIDispatcher port routing 통합 + 7 ops × 2 ports + record_sequence/mmc_* reject | Todo | - | Depends: T1, T2, T3 |
| T6 | MIDIKeyCommandsChannel `midi.send_*.keycmd` direct send path | Todo | - | Depends: T1, T4 |
| T7 | SystemDispatcher health detail (audited matrix + orphan ops) | Todo | - | Depends: None (independent) |
| T8 | Docs + Homebrew formula `xcode` 제거 + release.sh Issue #1 자동화 | Todo | - | Depends: T1-T7 (final integration step) |

## Review History

| Phase | Round | Verdict | P0 | P1 | P2 | P3 | Notes |
|-------|-------|---------|----|----|-----|-----|-------|
| 2     | 1     | HAS ISSUE | 0 | 4 | 5 | 0 | strategist+guardian+boomer 합의 |
| 2     | 2     | HAS ISSUE | 0 | 4 | 4 | 2 | Loop 2 — KeyCmd readiness gate, matrix 정확도, record_sequence scope, NoteSequenceParser API |
| 2     | 3     | MIXED → micro-revision | 0 | 1 (matrix) | 4 | 1 | strategist ALL PASS, guardian HAS ISSUE, boomer ESCALATE — Rules §8 3회 한도 → v0.4 micro-revision 후 진행 |
| 4     | 1     | HAS ISSUE | 0 | 9 | 11 | 6 | strategist HAS ISSUE / tester HAS ISSUE / guardian ALL PASS / boomer RECONSIDER — visibility 결함 + Live verification owning gap + T6 deps 누락 등 |
| 4     | 2     | micro-revision applied | - | - | - | - | T2/T4 visibility AC-0 추가, T6 deps T1+T3+T4, T2 empty port 정합화, T2 EC tests 16-18 추가, T4 invariant 양방향+T5 의존 명시, T5 string-equality 명시, T6 mock 재사용+pitch_bend convention, T8 AC-12 Live verification gate, target v3.1.5→v3.1.6 |
| 6     | 1     |         |    |    |     |     |       |

## v0.4 Micro-revision 항목 (Loop 3 후 적용 완료)

1. AC-3.4 matrix NavigateDispatcher 사실 정정 (smart_controls/plugin_windows/automation 별도 처리, automation.toggle_view = logic_navigate 노출, automation.set_mode primary MCU)
2. AC-5.1 health detail orphan ops 정확화
3. §4.1 router-gate available==false → `.portUnavailable` HC envelope 직접 반환 명시
4. §4.1 readiness bypass rationale chicken-and-egg framing
5. AC-2.6 notes ch field BREAKING 두번째 표 추가
6. §8.1 test 이름 + 카운트 정정 (8→7 ops, 16→14 cases, IgnoresWithWarning→RejectsPort)
7. §8.1 routingTable invariant test 추가 (parallel-list trap 방지)
8. §4.1 다이어그램 + §4.3 stale comment 정정
