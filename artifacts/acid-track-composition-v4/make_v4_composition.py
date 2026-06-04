#!/usr/bin/env python3
"""Build a MIDI-only v4 composition inspired by the reference analysis.

The final Logic project must not contain reference audio or separated stems.
This script writes Standard MIDI Files for software-instrument tracks only.
"""

from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path

import mido


ROOT = Path(__file__).resolve().parent
TMP_MIDI_ROOT = Path("/tmp/LogicProMCP")
MIDI_ROOT = ROOT / "midi"
TEMPO = 127.0
TICKS_PER_BEAT = 480
BEAT_MS = 60000.0 / TEMPO
STEP_MS = BEAT_MS / 4.0
BAR_MS = BEAT_MS * 4.0
TOTAL_BARS = 48


def cleanup_stale_tmp_midis() -> None:
    """Remove stale v4 temp MIDI files so repo tests do not see orphan SMFs."""
    if not TMP_MIDI_ROOT.exists():
        return
    for path in TMP_MIDI_ROOT.glob("v4_*.mid"):
        path.unlink()


@dataclass(frozen=True)
class Event:
    pitch: int
    step: float
    length: float
    velocity: int
    channel: int = 1

    def offset_ms(self) -> int:
        return int(round(self.step * STEP_MS))

    def duration_ms(self) -> int:
        return max(25, int(round(self.length * STEP_MS)))

    def spec(self) -> str:
        return f"{self.pitch},{self.offset_ms()},{self.duration_ms()},{self.velocity},{self.channel}"


@dataclass(frozen=True)
class Part:
    name: str
    patch: str
    role: str
    events: list[Event]


def ev(pitch: int, bar: int, pos: float, length: float, velocity: int, channel: int = 1) -> Event:
    return Event(pitch=pitch, step=bar * 16 + pos, length=length, velocity=velocity, channel=channel)


def write_midi(path: Path, part: Part) -> None:
    tempo = mido.bpm2tempo(TEMPO)
    mid = mido.MidiFile(type=1, ticks_per_beat=TICKS_PER_BEAT)
    track = mido.MidiTrack()
    mid.tracks.append(track)
    track.append(mido.MetaMessage("track_name", name=part.name, time=0))
    track.append(mido.MetaMessage("set_tempo", tempo=tempo, time=0))
    track.append(mido.MetaMessage("time_signature", numerator=4, denominator=4, time=0))

    timed = []
    for event in part.events:
        start = int(round(mido.second2tick(event.offset_ms() / 1000.0, TICKS_PER_BEAT, tempo)))
        end = int(round(mido.second2tick((event.offset_ms() + event.duration_ms()) / 1000.0, TICKS_PER_BEAT, tempo)))
        channel = max(0, min(15, event.channel - 1))
        timed.append((start, 1, mido.Message("note_on", note=event.pitch, velocity=event.velocity, channel=channel, time=0)))
        timed.append((end, 0, mido.Message("note_off", note=event.pitch, velocity=0, channel=channel, time=0)))

    last = 0
    for tick, order, message in sorted(timed, key=lambda item: (item[0], item[1])):
        message.time = max(0, tick - last)
        track.append(message)
        last = tick
    track.append(mido.MetaMessage("end_of_track", time=1))
    path.parent.mkdir(parents=True, exist_ok=True)
    mid.save(path)


def kick() -> list[Event]:
    events: list[Event] = []
    for bar in range(TOTAL_BARS):
        breakdown = 32 <= bar < 40
        for pos in (0, 4, 8, 12):
            if breakdown and pos in (4, 12):
                continue
            vel = 124 if bar >= 40 else 116
            events.append(ev(36, bar, pos, 1.65, vel, 10))
        if bar % 8 == 7:
            events.append(ev(36, bar, 14.5, 0.75, 86, 10))
            events.append(ev(36, bar, 15.25, 0.55, 78, 10))
    return events


def clap_snare() -> list[Event]:
    events: list[Event] = []
    for bar in range(TOTAL_BARS):
        if bar < 4 or 32 <= bar < 40:
            continue
        for pos in (4, 12):
            events.append(ev(39, bar, pos, 1.2, 110 if bar >= 16 else 96, 10))
            events.append(ev(38, bar, pos + 0.18, 0.75, 54 if bar < 40 else 70, 10))
        if bar >= 24 and bar % 4 == 3:
            for i, pos in enumerate((10.5, 11.25, 11.75, 15.0)):
                events.append(ev(38, bar, pos, 0.38, 52 + i * 8, 10))
    return events


def hats() -> list[Event]:
    events: list[Event] = []
    for bar in range(TOTAL_BARS):
        if bar >= 2:
            for pos in (2, 6, 10, 14):
                events.append(ev(46, bar, pos, 0.58, 84 if bar >= 16 else 70, 10))
        if bar >= 8 and not (32 <= bar < 36):
            for pos in (0, 3, 4, 7, 8, 11, 12, 15):
                vel = 48 if pos in (3, 7, 11, 15) else 40
                events.append(ev(42, bar, pos, 0.28, vel, 10))
        if bar >= 40:
            for pos in (1.5, 5.5, 9.5, 13.5):
                events.append(ev(44, bar, pos, 0.25, 48, 10))
    return events


def percussion() -> list[Event]:
    events: list[Event] = []
    for bar in range(TOTAL_BARS):
        if bar < 8:
            continue
        events.append(ev(56, bar, 7, 0.35, 56, 10))
        events.append(ev(51, bar, 11, 0.35, 50, 10))
        if bar >= 20:
            events.append(ev(50, bar, 3.5, 0.45, 64, 10))
            events.append(ev(48, bar, 15.5, 0.45, 72, 10))
        if bar % 8 == 7:
            fill = [47, 48, 50, 53, 50, 48, 47, 45]
            for i, pitch in enumerate(fill):
                events.append(ev(pitch, bar, 8 + i, 0.45, 72 + min(i * 4, 20), 10))
    return events


def acid_main() -> list[Event]:
    events: list[Event] = []
    pattern = [45, 45, 52, 45, 57, 45, 52, 55, 45, 48, 45, 43, 45, 52, 55, 57]
    accent = [118, 82, 104, 76, 112, 92, 88, 106, 120, 78, 98, 70, 116, 86, 108, 96]
    for bar in range(4, TOTAL_BARS):
        breakdown = 32 <= bar < 40
        for pos in range(16):
            if breakdown and pos not in (0, 3, 6, 10, 14):
                continue
            pitch = pattern[(pos + bar * 3) % len(pattern)]
            if bar >= 40 and pos in (1, 9, 15):
                pitch += 12
            length = 0.88 if pos in (0, 4, 8, 12) else 0.55
            events.append(ev(pitch, bar, pos, length, accent[pos], 1))
    return events


def acid_answer() -> list[Event]:
    events: list[Event] = []
    pattern = [57, 60, 57, 55, 52, 57, 64, 62, 57, 55, 52, 48, 45, 52, 55, 60]
    for bar in range(12, TOTAL_BARS):
        if 28 <= bar < 36 and bar % 2 == 0:
            continue
        if 36 <= bar < 40:
            positions = (0, 6, 10, 14)
        else:
            positions = (1, 5, 7, 9, 13, 15)
        for pos in positions:
            pitch = pattern[(bar + int(pos)) % len(pattern)]
            events.append(ev(pitch, bar, pos, 0.48, 76 + (int(pos) % 4) * 7, 1))
    return events


def sub_pump() -> list[Event]:
    events: list[Event] = []
    roots = [33, 31, 28, 33, 36, 31, 28, 31]
    for bar in range(8, TOTAL_BARS):
        if 32 <= bar < 40:
            continue
        root = roots[(bar // 2) % len(roots)]
        for pos in (0, 8):
            events.append(ev(root, bar, pos, 3.2, 76 if bar < 40 else 86, 1))
        if bar >= 40:
            events.append(ev(root + 12, bar, 14, 1.0, 52, 1))
    return events


def chord_stabs() -> list[Event]:
    events: list[Event] = []
    chords = [
        [57, 60, 64, 69],
        [55, 59, 62, 67],
        [52, 55, 59, 64],
        [60, 64, 67, 72],
    ]
    for bar in range(16, TOTAL_BARS):
        if 32 <= bar < 40 and bar % 2 == 1:
            continue
        chord = chords[(bar // 4) % len(chords)]
        positions = (0, 6, 10, 14) if bar >= 24 else (0, 10)
        for pos in positions:
            for i, pitch in enumerate(chord):
                events.append(ev(pitch, bar, pos, 1.15, 78 - i * 7, 1))
        if bar >= 40 and bar % 4 in (1, 3):
            for i, pitch in enumerate([69, 72, 76, 81]):
                events.append(ev(pitch, bar, 8, 0.8, 54 - i * 4, 1))
    return events


def metallic_lead() -> list[Event]:
    events: list[Event] = []
    motif = [81, 84, 83, 76, 81, 88, 86, 84]
    for bar in range(20, TOTAL_BARS):
        if bar % 4 not in (0, 3) and bar < 40:
            continue
        span = motif if bar >= 40 else motif[:4]
        for i, pitch in enumerate(span):
            events.append(ev(pitch, bar, 1 + i * (2 if bar >= 40 else 4), 0.42, 50 + i * 5, 1))
    return events


def vocal_like_synth() -> list[Event]:
    events: list[Event] = []
    phrase = [72, 69, 72, 76, 74, 72]
    for bar in range(24, TOTAL_BARS):
        if bar % 8 not in (2, 6):
            continue
        for i, pitch in enumerate(phrase):
            events.append(ev(pitch, bar, 2 + i * 1.5, 0.38, 46 + i * 4, 1))
    return events


def transitions() -> list[Event]:
    events: list[Event] = []
    for bar in (8, 16, 24, 32, 40, 44):
        start_bar = max(0, bar - 1)
        for i in range(8):
            events.append(ev(84 + i, start_bar, 8 + i, 0.7, 34 + i * 5, 1))
        events.append(ev(96, start_bar, 12, 4.0, 44, 1))
    events.append(ev(69, 47, 0, 15.5, 58, 1))
    events.append(ev(57, 47, 0, 15.5, 52, 1))
    return events


def build_parts() -> list[Part]:
    return [
        Part("v4_909_kick", "Electronic Drums/Roland TR-909", "909 four-on-floor kick with end-of-section doubles.", kick()),
        Part("v4_909_clap_snare", "Electronic Drums/Roland TR-909", "909 clap/snare backbeat and bar-end fills.", clap_snare()),
        Part("v4_909_hats", "Electronic Drums/Modern 909", "Offbeat open hats, closed-hat sixteenth ticks, final drive.", hats()),
        Part("v4_house_percussion", "Electronic Drums/Hacienda", "Additional tom/cowbell/perc movement and fills.", percussion()),
        Part("v4_acid_main_303", "Synthesizer/Bass/Acid Etched Bass", "Primary TB-303-style acid line in A minor.", acid_main()),
        Part("v4_acid_answer_303", "Synthesizer/Bass/Acid Wash Bass", "Higher resonant answer acid line, enters after intro.", acid_answer()),
        Part("v4_sub_pump", "Synthesizer/Bass/Deep Sub Bass", "Longer low root pulses to support the kick.", sub_pump()),
        Part("v4_rave_chord_stabs", "Synthesizer/Lead/Classic Rave Chord", "Warehouse chord stabs and offbeat harmonic accents.", chord_stabs()),
        Part("v4_metallic_lead", "Synthesizer/Lead/Chicago Chords", "Metallic syncopated lead hits in the second half.", metallic_lead()),
        Part("v4_vocal_like_synth", "Synthesizer/Sound Effects/Trill Riser", "Short synth phrases standing in for vocal/noise gestures without audio.", vocal_like_synth()),
        Part("v4_noise_transitions", "Synthesizer/Sound Effects/Zippy Build-Up", "Noise-rise MIDI gestures at section boundaries.", transitions()),
    ]


def main() -> None:
    ROOT.mkdir(parents=True, exist_ok=True)
    MIDI_ROOT.mkdir(parents=True, exist_ok=True)
    cleanup_stale_tmp_midis()

    parts = build_parts()
    output = []
    for part in parts:
        tmp_path = TMP_MIDI_ROOT / f"{part.name}.mid"
        artifact_path = MIDI_ROOT / f"{part.name}.mid"
        write_midi(artifact_path, part)
        output.append(
            {
                "name": part.name,
                "patch": part.patch,
                "role": part.role,
                "note_count": len(part.events),
                "midi_path": str(tmp_path),
                "artifact_midi_path": str(artifact_path),
            }
        )

    (ROOT / "v4-layer-specs.json").write_text(json.dumps(output, indent=2), encoding="utf-8")
    with (ROOT / "v4-import-requests.jsonl").open("w", encoding="utf-8") as file:
        for idx, part in enumerate(output, start=20):
            request = {
                "jsonrpc": "2.0",
                "id": idx,
                "method": "tools/call",
                "params": {
                    "name": "logic_midi",
                    "arguments": {
                        "command": "import_file",
                        "params": {"path": part["midi_path"]},
                    },
                },
            }
            file.write(json.dumps(request) + "\n")

    brief = [
        "# Acid Track v4 MIDI-Only Composition",
        "",
        "This version is composed, not recorded. It imports no reference audio and no separated stems.",
        "",
        f"- Tempo: {TEMPO} BPM",
        "- Key center: A minor",
        f"- Length: {TOTAL_BARS} bars",
        "- Output: Standard MIDI files for Logic software-instrument tracks only",
        "- Logic package: `acid-track-composed-midi-v4.logicx`",
        "- Verification: 11 MIDI regions, 0 packaged audio files, no imported reference/stem audio",
        "- Import runner: `import_v4_sequential.py` copies MIDI files to `/tmp/LogicProMCP` and waits for `verified:true` after each import",
        "",
        "## Parts",
    ]
    for part in output:
        brief.append(f"- {part['name']}: {part['patch']} ({part['note_count']} notes) - {part['role']}")
    (ROOT / "v4-brief.md").write_text("\n".join(brief) + "\n", encoding="utf-8")

    print(json.dumps({"parts": output}, indent=2))


if __name__ == "__main__":
    main()
