# Channel EQ AudioUnit Factory Metadata Spike

Date: 2026-07-07

## Scope

This adds a public AudioUnit metadata census script for
`PRD-channel-eq-verified-params-vNext` T0. It deliberately does **not** activate
Channel EQ verified params because the script cannot attach to Logic's active
hosted insert.

## Harness

- Script: `Scripts/spike-channel-eq-au-census.swift`
- API: `AudioComponentFindNext`, `AudioComponentInstanceNew`,
  `kAudioUnitProperty_ParameterList`, `kAudioUnitProperty_ParameterInfo`
- Provenance emitted for every parameter: `factory_metadata`
- Activation flag emitted for every parameter: `activation_evidence:false`

## Verified Smoke

Command:

```bash
swift Scripts/spike-channel-eq-au-census.swift
```

Observed:

- Apple `AUNBandEQ` was found.
- Parameter ids/ranges/names were emitted.
- Every record was marked `factory_metadata_only`.
- Summary explicitly stated this cannot activate registry entries by itself.

## Product Decision

Factory metadata may seed candidate ids/ranges for a future live census artifact,
but it is not State A evidence. T3 remains blocked until an active Logic insert
write/read-back surface exists.

## Live Logic AX Rerun

Command:

```bash
LOGIC_PRO_MCP_CHANNEL_EQ_CENSUS_TIMEOUT=12 \
LOGIC_PRO_MCP_BINARY=.build/release/LogicProMCP \
python3 Scripts/spike-channel-eq-census.py
```

Observed result:

- Logic Pro 12.3 was running with a visible scratch document.
- `logic_tracks.create_audio` created a fresh audio track and verified the track
  count delta.
- `logic_plugins.insert_verified` inserted `Channel EQ` at insert `0` and
  returned State A with `verify_source:"ax_plugin_inventory"`.
- Opening the Channel EQ editor for parameter traversal failed before a
  parameter census could be captured. The direct editor-opening script hit a
  script parse failure in this run, while the surrounding escape/cleanup
  System Events calls hit Apple-event permission denied (`-1743`) from this
  harness launch context.
- Cleanup track deletion was attempted but failed through the public
  `logic_tracks.delete` path because the AX menu delete command was not
  pressable in this context.

Verdict: **insert verification remains State A, parameter activation remains
blocked**. This rerun still provides no active hosted-insert parameter
write/read-back evidence, so no Channel EQ verified-param registry entries are
production-activated.
