# Issue #60 Ticket Board: Locale-Agnostic Logic UI Automation

**Issue**: https://github.com/MongLong0214/logic-pro-mcp/issues/60
**Status**: Partial - focused policy hardening PR

## Tickets

- [x] `I60-T1` Central AX locale policy and deterministic tests
  - Add `AXLocalePolicy` as the single home for unavoidable English/Korean UI labels in touched AX paths.
  - Move verified-plugin menu/dialog label matching and Save/Cancel button matching to the policy.
  - Document the matching order and State A readback requirement.

## Remaining Epic Work

- Audit every remaining AX text matcher outside the touched surfaces.
- Migrate AppleScript menu-label fallbacks where a safe AX replacement exists.
- Add live verification notes for English and Korean Logic UI before closing the epic.

## Verification

Completed on 2026-06-20:

- `swift test --filter AXLocalePolicy` - 3 tests passed.
- `swift test --filter AXLogicProElements` - 24 tests passed.
- `swift test --filter PluginInsertVerified` - 32 tests passed.
- `swift test --filter AccessibilityChannel` - 70 tests passed.
- `swift test --filter PluginGetInventory` - 12 tests passed.
- `git diff --check` - passed.
