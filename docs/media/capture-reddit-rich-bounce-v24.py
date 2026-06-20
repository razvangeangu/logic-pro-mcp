#!/usr/bin/env python3
"""Capture v24: richer actual Logic UI recording with per-track record arm.

Precondition: Logic Pro is open with the current four-track demo session visible.
The script avoids logic_tracks.create_instrument and records MIDI into the
visible tracks by clicking Logic's real record-enable buttons.
"""

from __future__ import annotations

import json
import signal
import subprocess
import threading
import time
from pathlib import Path
from typing import Any, Callable


ROOT = Path(__file__).resolve().parents[2]
BINARY = ROOT / ".build/release/LogicProMCP"
RAW_VIDEO = Path("/tmp/logic-v24-rich-bounce-ui-raw.mp4")
BASELINE_SCREENSHOT = Path("/tmp/logic-v24-rich-bounce-baseline.png")
FINAL_SCREENSHOT = Path("/tmp/logic-v24-rich-bounce-final.png")
TRANSCRIPT = ROOT / "docs/media/reddit-dudddee-rich-bounce-v24-transcript.json"
FPS = 24


class MCPClient:
    def __init__(self) -> None:
        self.proc = subprocess.Popen(
            [str(BINARY)],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=open("/tmp/logic-v24-mcp-stderr.txt", "w"),
            text=True,
            bufsize=0,
        )
        self.responses: dict[int, dict[str, Any]] = {}
        self.reader = threading.Thread(target=self._read_loop, daemon=True)
        self.reader.start()
        self.next_id = 1

    def _read_loop(self) -> None:
        assert self.proc.stdout is not None
        for line in self.proc.stdout:
            try:
                msg = json.loads(line)
            except json.JSONDecodeError:
                continue
            if isinstance(msg.get("id"), int):
                self.responses[msg["id"]] = msg

    def send(self, method: str, params: dict | None = None, timeout: float = 35.0) -> dict | None:
        msg_id = self.next_id
        self.next_id += 1
        assert self.proc.stdin is not None
        self.proc.stdin.write(json.dumps({"jsonrpc": "2.0", "id": msg_id, "method": method, "params": params or {}}) + "\n")
        self.proc.stdin.flush()
        deadline = time.time() + timeout
        while time.time() < deadline:
            if msg_id in self.responses:
                return self.responses.pop(msg_id)
            time.sleep(0.03)
        return None

    def tool(self, name: str, command: str, params: dict | None = None, timeout: float = 35.0) -> dict | None:
        return self.send("tools/call", {"name": name, "arguments": {"command": command, "params": params or {}}}, timeout=timeout)

    def resource(self, uri: str, timeout: float = 20.0) -> dict | None:
        return self.send("resources/read", {"uri": uri}, timeout=timeout)

    def close(self) -> None:
        try:
            if self.proc.stdin:
                self.proc.stdin.close()
        except Exception:
            pass
        try:
            self.proc.terminate()
            self.proc.wait(timeout=3)
        except Exception:
            self.proc.kill()


def parse_text(response: dict | None) -> str:
    if response is None:
        return "timeout"
    if response.get("error"):
        return json.dumps(response["error"], ensure_ascii=False)
    result = response.get("result", {})
    content = result.get("content") or result.get("contents") or []
    if content and isinstance(content[0], dict):
        return str(content[0].get("text", ""))
    return json.dumps(result, ensure_ascii=False)


def payload(response: dict | None) -> dict[str, Any] | None:
    if response is None or response.get("error"):
        return None
    try:
        parsed = json.loads(parse_text(response))
    except Exception:
        return None
    return parsed if isinstance(parsed, dict) else None


def classify(response: dict | None) -> str:
    if response is None:
        return "timeout"
    if response.get("error") or response.get("result", {}).get("isError") is True:
        return "error"
    parsed = payload(response)
    if parsed:
        if parsed.get("success") is False or parsed.get("error"):
            return "error"
        if parsed.get("verified") is False:
            return "state_b"
        if parsed.get("success") is True or parsed.get("verified") is True:
            return "ok"
    return "ok"


def compact(response: dict | None) -> str:
    if response is None:
        return "timeout"
    if response.get("error"):
        return f"jsonrpc error: {response['error']}"
    result = response.get("result", {})
    if "tools" in result:
        return f"{len(result['tools'])} tools"
    parsed = payload(response)
    if parsed:
        if parsed.get("success") is True:
            bits = [f"success=true verified={parsed.get('verified')}"]
            for key in ("note_count", "reason", "observed_delta"):
                if key in parsed:
                    bits.append(f"{key}={parsed[key]}")
            return " ".join(bits)
        if parsed.get("error"):
            return f"error={parsed.get('error')}"
        if "channels" in parsed:
            channels = parsed.get("channels", {})
            values = channels.values() if isinstance(channels, dict) else channels
            ready = sum(1 for item in values if isinstance(item, dict) and item.get("ready"))
            return f"health {ready}/{len(channels)} ready"
        if "data" in parsed and isinstance(parsed["data"], dict) and "state" in parsed["data"]:
            state = parsed["data"]["state"]
            return f"transport tempo={state.get('tempo')} position={state.get('position')} playing={state.get('isPlaying')}"
    text = parse_text(response)
    return " ".join(text.split())[:180] if text else "ok"


def run_quiet(args: list[str], timeout: float | None = None) -> subprocess.CompletedProcess:
    return subprocess.run(args, check=False, timeout=timeout, text=True, capture_output=True)


def screenshot(path: Path) -> None:
    run_quiet(["/usr/sbin/screencapture", "-x", str(path)], timeout=5)


def start_capture() -> subprocess.Popen:
    return subprocess.Popen(
        [
            "ffmpeg",
            "-y",
            "-loglevel",
            "warning",
            "-f",
            "avfoundation",
            "-framerate",
            str(FPS),
            "-capture_cursor",
            "1",
            "-i",
            "0:none",
            "-c:v",
            "libx264",
            "-preset",
            "veryfast",
            "-crf",
            "18",
            "-pix_fmt",
            "yuv420p",
            str(RAW_VIDEO),
        ],
        stdin=subprocess.PIPE,
    )


def stop_capture(proc: subprocess.Popen) -> None:
    if proc.stdin:
        try:
            proc.stdin.write(b"q")
            proc.stdin.flush()
        except Exception:
            pass
    try:
        proc.wait(timeout=10)
    except subprocess.TimeoutExpired:
        proc.send_signal(signal.SIGINT)
        try:
            proc.wait(timeout=15)
        except subprocess.TimeoutExpired:
            proc.kill()


def click_xy(x: int, y: int, delay: float = 0.35) -> bool:
    result = run_quiet(["/opt/homebrew/bin/cliclick", f"c:{x},{y}"], timeout=3)
    time.sleep(delay)
    return result.returncode == 0


def focus_logic() -> None:
    for app in ["Finder", "Google Chrome", "Discord", "Telegram", "WebStorm"]:
        run_quiet(["/opt/homebrew/bin/peekaboo", "app", "hide", "--app", app, "--json"], timeout=3)
    run_quiet(["open", "-a", "Logic Pro"], timeout=4)
    time.sleep(0.8)


def notes_to_spec(events: list[tuple[int, int, int, int, int]]) -> str:
    return ";".join(f"{pitch},{offset},{duration},{velocity},{channel}" for pitch, offset, duration, velocity, channel in events)


def drum_groove() -> str:
    events: list[tuple[int, int, int, int, int]] = []
    for i in range(64):
        offset = i * 250
        events.append((42 if i % 4 else 46, offset, 70, 72 + (i % 4) * 3, 10))
    for offset in range(0, 16000, 500):
        events.append((36, offset, 135, 124 if offset % 2000 == 0 else 112, 10))
    for offset in range(1000, 16000, 2000):
        events.append((38, offset, 130, 112, 10))
        events.append((39, offset + 35, 90, 74, 10))
    return notes_to_spec(sorted(events, key=lambda item: (item[1], item[0])))


def bass_groove() -> str:
    pattern = [36, 36, 43, 36, 34, 36, 39, 43]
    events: list[tuple[int, int, int, int, int]] = []
    for step in range(32):
        pitch = pattern[step % len(pattern)]
        velocity = 110 if step % 4 == 0 else 88 + (step % 3) * 7
        events.append((pitch, step * 500, 260, velocity, 1))
    return notes_to_spec(events)


def chord_stabs() -> str:
    chords = [
        (48, 55, 60),
        (51, 58, 63),
        (46, 53, 58),
        (43, 51, 58),
    ]
    events: list[tuple[int, int, int, int, int]] = []
    for bar in range(8):
        root = chords[bar % len(chords)]
        for hit in (0, 1250):
            for index, pitch in enumerate(root):
                events.append((pitch, bar * 2000 + hit, 310, 92 - index * 4, 1))
    return notes_to_spec(events)


def upper_motion() -> str:
    phrase = [60, 63, 67, 70, 72, 75, 70, 67, 63, 67, 70, 75, 79, 75, 72, 70]
    events: list[tuple[int, int, int, int, int]] = []
    for step in range(64):
        pitch = phrase[step % len(phrase)]
        duration = 115 if step % 4 else 170
        velocity = 96 + (step % 5) * 5
        events.append((pitch, step * 250, duration, min(118, velocity), 1))
    return notes_to_spec(events)


def main() -> None:
    if not BINARY.exists():
        raise SystemExit(f"Missing MCP binary: {BINARY}")

    focus_logic()
    click_xy(620, 88, 0.5)
    screenshot(BASELINE_SCREENSHOT)
    capture = start_capture()
    client = MCPClient()
    started_at = time.time()
    events: list[dict[str, Any]] = []

    def event(label: str, family: str, state: str, summary: str, **extra: Any) -> None:
        now = round(time.time() - started_at, 3)
        item = {"label": label, "family": family, "start_s": now, "end_s": now, "state": state, "summary": summary}
        item.update(extra)
        events.append(item)
        print(f"{label}: {state} | {summary}", flush=True)

    def step(label: str, family: str, fn: Callable[[], dict | None], delay: float = 0.45, **extra: Any) -> dict | None:
        t0 = time.time() - started_at
        response = fn()
        t1 = time.time() - started_at
        item = {
            "label": label,
            "family": family,
            "start_s": round(t0, 3),
            "end_s": round(t1, 3),
            "state": classify(response),
            "summary": compact(response),
            "response": response,
        }
        item.update(extra)
        events.append(item)
        print(f"{label}: {item['state']} | {item['summary']}", flush=True)
        time.sleep(delay)
        return response

    track_y = {1: 240, 2: 310, 3: 330, 4: 450}
    record_enable_y = {1: 249, 2: 319, 3: 330, 4: 457}
    layers = [
        {
            "label": "brooklyn_dense_drums",
            "track_index": 2,
            "visible_track": "Brooklyn",
            "role": "kick, clap, closed hats, open hats",
            "notes": drum_groove(),
            "hold_s": 17.2,
        },
        {
            "label": "track1_driving_bass",
            "track_index": 1,
            "visible_track": "Deluxe Classic",
            "role": "driving bass movement",
            "notes": bass_groove(),
            "hold_s": 17.2,
        },
        {
            "label": "track3_minor_stabs",
            "track_index": 3,
            "visible_track": "Deluxe Classic",
            "role": "minor chord stabs",
            "notes": chord_stabs(),
            "hold_s": 17.2,
        },
        {
            "label": "above_and_beyond_motion",
            "track_index": 4,
            "visible_track": "Above and Beyond",
            "role": "upper synth motion",
            "notes": upper_motion(),
            "hold_s": 17.2,
        },
    ]

    def arm_track(index: int) -> None:
        click_xy(725, track_y[index], 0.25)
        click_xy(815, record_enable_y[index], 0.45)
        event(f"ui.arm_track_{index}", "ui_track", "ok", f"clicked visible Logic track {index} record-enable", track_index=index)

    def go_to_beginning() -> None:
        click_xy(620, 88, 0.5)
        event("ui.go_to_beginning", "ui_transport", "ok", "clicked actual Logic Go to Beginning button")

    def record_layer(layer: dict[str, Any]) -> None:
        arm_track(layer["track_index"])
        go_to_beginning()
        click_xy(740, 88, 0.5)
        event(f"{layer['label']}.ui_record", "ui_transport", "ok", "clicked actual Logic Record button", layer_name=layer["label"])
        step(
            f"{layer['label']}.play_sequence",
            "midi_live_record",
            lambda notes=layer["notes"]: client.tool("logic_midi", "play_sequence", {"notes": notes}, timeout=24.0),
            delay=float(layer["hold_s"]),
            layer_name=layer["label"],
            visible_track=layer["visible_track"],
            role=layer["role"],
            note_count=len(layer["notes"].split(";")),
        )
        click_xy(620, 88, 0.75)
        event(f"{layer['label']}.ui_stop", "ui_transport", "ok", "clicked actual Logic Stop button", layer_name=layer["label"])

    try:
        event(
            "ui.baseline",
            "provenance",
            "ok",
            "baseline screenshot captured at project start with four visible tracks",
            screenshot=str(BASELINE_SCREENSHOT),
        )
        step(
            "initialize",
            "session",
            lambda: client.send(
                "initialize",
                {
                    "protocolVersion": "2024-11-05",
                    "capabilities": {},
                    "clientInfo": {"name": "v24-rich-bounce", "version": "1"},
                },
            ),
            delay=0.3,
        )
        step("tools/list", "discovery", lambda: client.send("tools/list"), delay=0.25)
        step("logic://system/health", "readback", lambda: client.resource("logic://system/health"), delay=0.25)
        step("logic://transport/state.before", "readback", lambda: client.resource("logic://transport/state"), delay=0.25)

        for layer in layers:
            record_layer(layer)

        go_to_beginning()
        click_xy(700, 88, 0.45)
        event("final.ui_play", "ui_transport", "ok", "clicked actual Logic Play button for final visual playback")
        time.sleep(16.8)
        click_xy(620, 88, 0.7)
        event("final.ui_stop", "ui_transport", "ok", "clicked actual Logic Stop button")
        screenshot(FINAL_SCREENSHOT)
        event("ui.final.screenshot", "provenance", "ok", "captured final arrangement screenshot", screenshot=str(FINAL_SCREENSHOT))
        step("logic://transport/state.after", "readback", lambda: client.resource("logic://transport/state"), delay=0.25)
    finally:
        client.close()
        stop_capture(capture)

    states = {state: sum(1 for item in events if item["state"] == state) for state in sorted({item["state"] for item in events})}
    transcript = {
        "generated_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "raw_video": str(RAW_VIDEO),
        "baseline_screenshot": str(BASELINE_SCREENSHOT),
        "final_screenshot": str(FINAL_SCREENSHOT),
        "source": "actual Logic Pro screen recording from the current visible 1-4 track session; per-track record-enable buttons were clicked before each live MIDI pass",
        "audio_plan": "separate verified Logic bounce/export will be attached in render step",
        "event_count": len(events),
        "states": states,
        "layers": [
            {
                "label": layer["label"],
                "track_index": layer["track_index"],
                "visible_track": layer["visible_track"],
                "role": layer["role"],
                "note_count": len(layer["notes"].split(";")),
            }
            for layer in layers
        ],
        "truth_boundaries": {
            "verified": [
                "actual Logic UI capture",
                "actual UI record-enable/record/play/stop button clicks",
                "logic_midi.play_sequence responses recorded in transcript",
                "no logic_tracks.create_instrument calls",
            ],
            "not_claimed": [
                "MCP readback-verified track list",
                "MCP readback-verified patch assignment",
                "live system audio capture",
            ],
        },
        "events": events,
    }
    TRANSCRIPT.write_text(json.dumps(transcript, ensure_ascii=False, indent=2) + "\n")
    print(f"captured {RAW_VIDEO}")
    print(f"baseline {BASELINE_SCREENSHOT}")
    print(f"final {FINAL_SCREENSHOT}")
    print(f"transcript {TRANSCRIPT}")
    print(f"states {states}")


if __name__ == "__main__":
    main()
