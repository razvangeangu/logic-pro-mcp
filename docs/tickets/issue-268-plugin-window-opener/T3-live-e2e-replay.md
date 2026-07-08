# T3 - Live E2E Replay

## Goal

Replay the local Logic Pro 12.3 issue #268 scenario through the actual MCP
surface.

## Acceptance

- [x] Preflight `get_inventory` confirms target Compressor slot State A.
- [x] `set_param_verified` on Compressor `threshold` returns State A.
- [x] Post-check confirms Logic health remains OK.
- [x] Project is not dirtied by a failed attempt; successful attempt is either
  safe apply-back or performed in a scratch/duplicate project.

## Verification

- Live MCP replay through the branch release binary:
  - `logic_plugins.get_inventory` found the target Compressor slot as State A.
  - `logic_plugins.set_param_verified` for Compressor `threshold` returned
    `state:"A"`, `verified:true`, `write_source:"ax_plugin_window"`, and
    `verify_source:"ax_plugin_window"`.
  - `logic_system.health` remained ready for the required AX/AppleScript/event
    surfaces.
- A second replay explicitly targeted track 2 insert 1 to avoid relying on the
  previously-open track 1 plugin window; it also returned State A verified.
- Public PR/issue text must summarize this without local absolute paths.
