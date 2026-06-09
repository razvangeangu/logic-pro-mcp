# T2: AppleScriptChannel.currentDocumentPath static helper

> Historical record (2026-06-09 docs refresh): latest production-readiness and live E2E evidence is in `README.md`, `CHANGELOG.md`, and `docs/live-verify-v3.4.5.md`; this file remains preserved implementation context.

**PRD Ref**: PRD-issue7-logic12-read-paths > US-1, US-2 (input)
**Priority**: P2 (Medium)
**Size**: S (< 1h)
**Status**: Todo
**Depends On**: None

---

## 1. Objective
Promote the existing `AppleScriptChannel.logicCurrentDocumentPath()` instance method to a static `@Sendable` helper so `LogicProjectFileReader.Runtime.production` can wire it without instantiating a channel.

## 2. Acceptance Criteria
- [ ] AC-1: `static func currentDocumentPath() async -> String?` exposed on `AppleScriptChannel`.
- [ ] AC-2: Returns trimmed path string or nil on failure / empty document set.
- [ ] AC-3: Existing `logicCurrentDocumentPath()` instance method delegates to the static (no behavioural change).
- [ ] AC-4: TCC denial / Logic-not-running paths return nil cleanly.

## 3. TDD Spec (Red Phase)

### 3.1 Test Cases
Append to `Tests/LogicProMCPTests/AppleScriptChannelTests.swift`:

| # | Test Name | Type | Expected |
|---|-----------|------|----------|
| 1 | `currentDocumentPath_emptyResult_returnsNil` | Unit | runtime returns `""` → nil |
| 2 | `currentDocumentPath_pathString_returnsTrimmed` | Unit | runtime returns `" /Users/x/A.logicx \n"` → `"/Users/x/A.logicx"` |
| 3 | `currentDocumentPath_appleScriptError_returnsNil` | Unit | runtime returns `.error("TCC")` → nil |
| 4 | `instanceMethodDelegatesToStatic` | Unit | wires same Runtime, asserts identical output |

### 3.2 Mock/Setup
Use existing `AppleScriptRecorder` test double + override `runScript` to return controlled JSON wrapper.

## 4. Implementation Guide

### 4.1 Files to Modify
| File | Change | Description |
|------|--------|-------------|
| `Sources/LogicProMCP/Channels/AppleScriptChannel.swift` | Modify | Add static; keep instance as delegate |
| `Tests/LogicProMCPTests/AppleScriptChannelTests.swift` | Modify | +4 tests |

### 4.2 Implementation Steps (Green)
1. Move script body to `static func currentDocumentPathScript() -> String` (already exists as private — make file-scoped or static).
2. Add `static func currentDocumentPath(runtime: Runtime = .production) async -> String?` — calls `runtime.runScript`, parses wrapper, returns trimmed string or nil.
3. Convert instance `logicCurrentDocumentPath()` to call `Self.currentDocumentPath(runtime: self.runtime)`.

## 5. Edge Cases
- E13: TCC denial → nil
- E14: No AX trust — AppleScript still works (Automation TCC), nil only if Logic has no document

## 6. Review Checklist
- [ ] Red: 4 tests fail
- [ ] Green: 4 tests pass; existing AppleScriptChannel tests unchanged
- [ ] No public API removed (instance method preserved)
