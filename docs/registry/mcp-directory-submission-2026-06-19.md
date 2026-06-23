# MCP Directory and Registry Submission Pack

Date: 2026-06-19
Repo: https://github.com/MongLong0214/logic-pro-mcp
Version: v3.7.0
Status: Official MCP Registry metadata refresh for v3.7.0 published via GitHub OIDC workflow; downstream directories pending ingestion or review.

This is the reusable listing package for MCP discovery surfaces: the Official MCP Registry, GitHub MCP Registry, Glama, PulseMCP, and curated lists such as awesome-mcp-servers.

## Current Submission Status

Checked: 2026-06-23 v3.7.0 release

| Surface | Status | Verification |
|---------|--------|--------------|
| Official MCP Registry | v3.7.0 metadata publish workflow passed | Publish workflow run `27997872931` completed successfully: publisher download, metadata validation, GitHub OIDC login, and publish all passed. Root `server.json` is `3.7.0`. A prior manual run exposed a bad `releases/download/latest` publisher URL; commit `56d711b` fixed it to `releases/latest/download`. |
| GitHub MCP Registry | Not visible yet | `https://github.com/mcp?search=Logic+Pro+MCP` shows no matching MCPs. GitHub's public docs/blog describe this surface as curated; after official publication, the listed inclusion path is an email request to `partnerships@github.com`. |
| Glama | Not visible yet | `https://glama.ai/mcp/servers?query=logic%20pro%20mcp` does not show this server, and `https://glama.ai/mcp/servers/MongLong0214/logic-pro-mcp` returns 404. The unauthenticated submit endpoint redirects to sign-up, and the UI sign-up path is protected by reCAPTCHA. |
| PulseMCP | Existing community listing; official registry ingest pending | `https://www.pulsemcp.com/servers/monglong-logic-pro` is live, but still uses `com.pulsemcp.mirror/monglong-logic-pro`. PulseMCP's submit page says official-registry entries are ingested daily and processed weekly; listing adjustments go through `hello@pulsemcp.com`. |
| awesome-mcp-servers | Pull request open and checks passing | `https://github.com/punkpeye/awesome-mcp-servers/pull/8322` is open/CLEAN with `check-submission` success and labels `has-glama`, `has-emoji`, `valid-name`. |

## Source Facts

- Name: Logic Pro MCP
- Registry name: `io.github.MongLong0214/logic-pro-mcp`
- One-line description: Local MCP server for stateful, fail-closed Logic Pro control and live project readback.
- Repository: https://github.com/MongLong0214/logic-pro-mcp
- Release: https://github.com/MongLong0214/logic-pro-mcp/releases/tag/v3.7.0
- License: MIT
- Platform: macOS 14+
- Logic Pro: 12.0.1+
- MCP transport: stdio
- Command: `LogicProMCP`
- Stable install path: Homebrew tap plus pinned GitHub release artifact
- Surface: 10 tools, 18 resources, 11 resource templates, 7 native macOS control channels
- Icon: https://raw.githubusercontent.com/MongLong0214/logic-pro-mcp/main/docs/media/logic-pro-mcp-thumbnail.png

## Official MCP Registry

Root `server.json` has been published to the Official MCP Registry for `io.github.MongLong0214/logic-pro-mcp`; v3.7.0 metadata publish workflow run `27997872931` passed on 2026-06-23.

The registry rejects duplicate publication of the same version, so `3.6.0` cannot be republished just to refresh metadata fields. Icon/discovery metadata added after the first `3.6.0` publish is now carried by the v3.7.0 staged metadata.

Important fit note: the official registry package types currently cover npm, PyPI, NuGet, Cargo, OCI, and MCPB. This project is currently distributed as a macOS Homebrew formula plus GitHub release tarball. Because Homebrew/GitHub release tarballs are not first-class official package types, the current `server.json` is intentionally metadata-only: it uses `websiteUrl`, `repository`, and publisher-provided install metadata instead of a `packages` entry.

Publish posture:

- Use the root `server.json` as the canonical registry metadata.
- Keep `.github/workflows/publish-mcp.yml` enabled after merge so release publications can refresh official registry metadata from tags via GitHub OIDC.
- If a future official registry update rejects metadata-only servers, use one of these follow-ups:
  - Add a real MCPB release asset if MCPB is suitable for a local macOS binary server.
  - Ask the registry working group whether Homebrew formula support is planned.
  - Avoid OCI as a primary path for now; Logic Pro control requires host macOS UI access, so a containerized server would be misleading for users.

## Directory Listing Copy

Title:

Logic Pro MCP

Short description:

Local MCP server for stateful, fail-closed Logic Pro control and live project readback.

Long description:

Logic Pro MCP gives Claude, Cursor, and other MCP clients a structured control plane for Logic Pro. It exposes a small write surface for transport, tracks, MIDI, mixer, plugins, edit, navigation, project lifecycle, and system health, plus read resources for live project state. The key design point is honesty: operations return confirmed, uncertain, or failed states instead of turning fragile UI automation into fake success. It is built for macOS producers and agent workflow authors who want Logic Pro automation with provenance, permission checks, and fail-closed safety gates.

Install:

```bash
brew tap MongLong0214/logic-pro-mcp https://github.com/MongLong0214/logic-pro-mcp
brew trust monglong0214/logic-pro-mcp
brew install logic-pro-mcp
```

Client config:

```json
{
  "mcpServers": {
    "logic-pro": {
      "command": "LogicProMCP"
    }
  }
}
```

Claude Code:

```bash
claude mcp add --scope user logic-pro -- LogicProMCP
```

Setup check:

```bash
LogicProMCP --check-permissions
```

Recommended tags:

- logic-pro
- music-production
- daw
- macos
- swift
- mcp
- model-context-protocol
- ai-agents
- automation

Suggested categories:

- Music production
- Desktop automation
- macOS
- Developer tools
- Agent tools

Safety notes:

- Local stdio server; not a remote hosted API.
- Requires macOS Accessibility and Automation permissions.
- Destructive project operations require confirmation metadata.
- High-risk operations use Honest Contract envelopes: confirmed, uncertain, or failed.
- Published v3.7.0 artifacts are universal macOS binaries with release SHA evidence.

## Awesome List Entry

```markdown
- [Logic Pro MCP](https://github.com/MongLong0214/logic-pro-mcp) - Local macOS MCP server that gives agents stateful, fail-closed control of Logic Pro with live readback for transport, tracks, MIDI, mixer, plugins, project lifecycle, and system health.
```

## Glama / PulseMCP Submission Text

```text
Logic Pro MCP is a local macOS MCP server for controlling Logic Pro from Claude, Cursor, and other MCP clients. It exposes 10 tools, 18 read resources, and 11 resource templates across native macOS control channels, with an explicit honest-contract model for confirmed, uncertain, and failed operations. Use it when an agent needs to inspect or operate Logic sessions without pretending that fragile UI automation is verified state.
```

PulseMCP note: PulseMCP's submit page says it ingests the Official MCP Registry daily and processes entries weekly; direct manual server submissions should use email only after a week or for listing adjustments.

Glama note: Glama describes the Official MCP Registry as the canonical source and indexes MCP servers from the broader ecosystem. Search did not show this server immediately after publish, so directory visibility may lag behind official registry publication.

## GitHub MCP Registry / GitHub Discovery Text

```text
Logic Pro MCP connects MCP clients to Logic Pro through a local stdio server. It focuses on practical DAW agent workflows: read project state, operate transport, create and inspect tracks and MIDI, query mixer and plugin state, run setup checks, and keep destructive or uncertain operations fail-closed. The server is distributed as a Homebrew-installed macOS binary and documents release evidence, setup, troubleshooting, and API surfaces in the repository.
```

## Submission Checklist

- Confirm root `server.json` remains valid against the official schema.
- Keep repository topics aligned with the tags above.
- Keep README top section aligned with the directory short description.
- Verify the v3.7.0 release URL and Homebrew formula SHA before publishing.
- Verify downstream directory ingestion by searching GitHub MCP Registry, Glama, and PulseMCP for `Logic Pro MCP`.
