# I60-T1 - Centralized AX Locale Policy

**Status**: Done
**Size**: M
**Issue**: https://github.com/MongLong0214/logic-pro-mcp/issues/60

## Goal

Centralize unavoidable localized UI labels used by touched AX paths and make the safety policy explicit.

## Scope

- Add `AXLocalePolicy` with label sets, menu paths, and AX element matching helpers.
- Cover English and Korean labels for verified-plugin menu reveal/cleanup, Undo rollback, Go to Position dialog dismissal, Save/Cancel buttons, and plugin format leaves.
- Update touched callers to use the central policy.
- Add deterministic tests for label and menu matching.
- Add a repo-level policy document.

## Acceptance Criteria

- Touched AX paths no longer carry ad hoc English/Korean label arrays inline.
- Tests cover English and Korean variants for the centralized policy.
- Documentation states localized labels are compatibility hints, not success evidence.
- Mutating paths remain readback-gated.

## Verification

- `swift test --filter AXLocalePolicy` - 3 tests passed.
- `swift test --filter AXLogicProElements` - 24 tests passed.
- `swift test --filter PluginInsertVerified` - 32 tests passed.
- `swift test --filter AccessibilityChannel` - 70 tests passed.
- `swift test --filter PluginGetInventory` - 12 tests passed.
- `git diff --check` - passed.
