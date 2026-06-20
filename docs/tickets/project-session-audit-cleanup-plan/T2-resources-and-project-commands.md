# T2: Resources And Project Commands

**Status**: Done
**Issue**: #28

## Scope

Expose audit and cleanup-plan data through read-only MCP resources and `logic_project` commands.

## Acceptance Criteria

- `logic://project/audit` returns audit JSON.
- `logic://project/cleanup-plan` returns cleanup-plan JSON.
- `logic_project audit` and `logic_project cleanup_plan` return the same schemas without destructive-policy gates.
- ResourceProvider and server handler tests include the new resources.

## Verification

- `swift test --filter ResourceProvider`
- `swift test --filter LogicProServerHandler`
- `swift test --filter LogicProServerTransport`
