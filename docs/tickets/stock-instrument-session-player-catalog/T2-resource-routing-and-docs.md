# I31-T2: Resource Routing and Docs

## Scope

Expose stock instrument and Session Player intelligence through MCP read-only resources.

## Acceptance

- Root, detail, and search routes return JSON with validation state.
- Malformed paths, fragments, unknown query parameters, doubled slashes, and encoded path aliases fail closed.
- `ResourceProvider`, `manifest.json`, README, and API docs advertise 16 resources and 10 templates.

## Result

Implemented in `ResourceHandlers.swift`, `ResourceProvider.swift`, `manifest.json`, `README.md`, and `docs/API.md`.
