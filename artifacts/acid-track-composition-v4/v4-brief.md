# Acid Track v4 MIDI-Only Composition

This version is composed, not recorded. It imports no reference audio and no separated stems.

- Tempo: 127.0 BPM
- Key center: A minor
- Length: 48 bars
- Output: Standard MIDI files for Logic software-instrument tracks only
- Logic package: `acid-track-composed-midi-v4.logicx`
- Verification: 11 MIDI regions, 0 packaged audio files, no imported reference/stem audio
- Import runner: `import_v4_sequential.py` copies MIDI files to `/tmp/LogicProMCP` and waits for `verified:true` after each import

## Production Validation

- Validated live against Logic Pro 12.2 via `.build/release/LogicProMCP`.
- MCP health reported all 7 channels ready before import/save validation.
- `logic_transport set_tempo` verified `127 BPM`.
- `logic_project save_as` returned Honest Contract `verified:true`; observed package mtime was `2026-06-04T14:38:48Z`.
- Package-level `ProjectData` inspection found every expected v4 region name listed below. AX viewport readback can show fewer visible rows, so the package check is the authoritative completion evidence for this artifact.
- No reference recording, separated stem, or packaged audio file is required for this version; it is a composed MIDI/software-instrument arrangement.

## Parts
- v4_909_kick: Electronic Drums/Roland TR-909 (188 notes) - 909 four-on-floor kick with end-of-section doubles.
- v4_909_clap_snare: Electronic Drums/Roland TR-909 (160 notes) - 909 clap/snare backbeat and bar-end fills.
- v4_909_hats: Electronic Drums/Modern 909 (504 notes) - Offbeat open hats, closed-hat sixteenth ticks, final drive.
- v4_house_percussion: Electronic Drums/Hacienda (176 notes) - Additional tom/cowbell/perc movement and fills.
- v4_acid_main_303: Synthesizer/Bass/Acid Etched Bass (616 notes) - Primary TB-303-style acid line in A minor.
- v4_acid_answer_303: Synthesizer/Bass/Acid Wash Bass (184 notes) - Higher resonant answer acid line, enters after intro.
- v4_sub_pump: Synthesizer/Bass/Deep Sub Bass (72 notes) - Longer low root pulses to support the kick.
- v4_rave_chord_stabs: Synthesizer/Lead/Classic Rave Chord (400 notes) - Warehouse chord stabs and offbeat harmonic accents.
- v4_metallic_lead: Synthesizer/Lead/Chicago Chords (104 notes) - Metallic syncopated lead hits in the second half.
- v4_vocal_like_synth: Synthesizer/Sound Effects/Trill Riser (36 notes) - Short synth phrases standing in for vocal/noise gestures without audio.
- v4_noise_transitions: Synthesizer/Sound Effects/Zippy Build-Up (56 notes) - Noise-rise MIDI gestures at section boundaries.
