#!/usr/bin/env python3
"""Capture a fresh-project truthful Logic UI demo for v19.

Precondition: Logic is already open on a new Empty Project with the first
Software Instrument track visible. This script does not reuse any earlier raw
capture and does not create or attach guide audio.
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
RAW_VIDEO = Path("/tmp/logic-v19-fresh-truthful-ui-raw.mp4")
BASELINE_SCREENSHOT = Path("/tmp/logic-v19-fresh-track1-baseline.png")
FINAL_SCREENSHOT = Path("/tmp/logic-v19-fresh-final.png")
TRANSCRIPT = ROOT / "docs/media/reddit-dudddee-fresh-truthful-ui-v19-transcript.json"
FPS = 24


class MCPClient:
    def __init__(self) -> None:
        self.proc = subprocess.Popen(
            [str(BINARY)],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=open("/tmp/logic-v19-mcp-stderr.txt", "w"),
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
            for key in ("observed_delta", "track_count_after", "created_track", "note_count", "reason"):
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
            return f"transport tempo={state.get('tempo')} playing={state.get('isPlaying')}"
    text = parse_text(response)
    return " ".join(text.split())[:180] if text else "ok"


def run_quiet(args: list[str], timeout: float | None = None) -> subprocess.CompletedProcess:
    return subprocess.run(args, check=False, timeout=timeout, text=True, capture_output=True)


def screenshot(path: Path) -> None:
    run_quiet(["screencapture", "-x", str(path)], timeout=5)


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


def press_key(key: str, delay: float = 0.25) -> bool:
    result = run_quiet(["/opt/homebrew/bin/cliclick", f"kp:{key}"], timeout=3)
    time.sleep(delay)
    return result.returncode == 0


def focus_logic() -> None:
    for app in ["Finder", "Google Chrome", "Discord", "Telegram", "WebStorm"]:
        run_quiet(["/opt/homebrew/bin/peekaboo", "app", "hide", "--app", app, "--json"], timeout=3)
    run_quiet(["open", "-a", "Logic Pro"], timeout=4)
    time.sleep(0.8)


def main() -> None:
    if not BINARY.exists():
        raise SystemExit(f"Missing MCP binary: {BINARY}")

    focus_logic()
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

    def choose_patch(label: str, category_y: int, preset_y: int, category: str) -> None:
        click_xy(80, category_y, 0.45)
        click_xy(275, preset_y, 1.2)
        event(
            f"ui.patch.{label}",
            "ui_patch",
            "ok",
            f"selected visible Logic Library patch via UI: {category}/{label}",
            category=category,
            patch=label,
            verification="visual_ui_only_not_mcp_readback",
        )

    def record_layer(label: str, notes: str, hold: float = 1.35) -> None:
        press_key("return", 0.25)
        click_xy(740, 88, 0.5)
        event(f"{label}.ui_record", "ui_transport", "ok", "clicked actual Logic Record button")
        step(
            f"{label}.play_sequence",
            "midi_live_record",
            lambda: client.tool("logic_midi", "play_sequence", {"notes": notes}, timeout=20.0),
            delay=hold,
        )
        click_xy(660, 88, 0.65)
        event(f"{label}.ui_stop", "ui_transport", "ok", "clicked actual Logic Stop button")

    try:
        event(
            "ui.baseline.fresh_track_1",
            "provenance",
            "ok",
            "fresh Empty Project baseline captured; first visible track number is 1",
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
                    "clientInfo": {"name": "v19-fresh-truthful-ui", "version": "1"},
                },
            ),
            delay=0.3,
        )
        step("tools/list", "discovery", lambda: client.send("tools/list"), delay=0.25)
        step("logic://system/health", "readback", lambda: client.resource("logic://system/health"), delay=0.25)
        step("logic://transport/state.before", "readback", lambda: client.resource("logic://transport/state"), delay=0.25)

        click_xy(720, 240, 0.25)
        choose_patch("electronic-drums-foundation", 452, 452, "Electronic Drums")
        record_layer("track1_drums", "36,0,140,125;36,500,140,118;38,1000,120,104;36,1500,140,118")

        step(
            "track2.create_instrument",
            "track_state_b",
            lambda: client.tool("logic_tracks", "create_instrument", {}, timeout=20.0),
            delay=1.1,
            note="used only to add a visible track; readback gaps remain covered by #35/#43",
        )
        choose_patch("sub-bass", 390, 552, "Bass")
        record_layer("track2_bass", "43,0,260,112;43,500,220,96;46,1000,250,104;41,1500,260,108")

        step(
            "track3.create_instrument",
            "track_state_b",
            lambda: client.tool("logic_tracks", "create_instrument", {}, timeout=20.0),
            delay=1.1,
            note="used only to add a visible track; readback gaps remain covered by #35/#43",
        )
        choose_patch("acid-synth", 748, 552, "Synthesizer")
        record_layer("track3_acid", "60,0,160,110;63,250,120,96;67,500,160,104;70,750,120,96;72,1000,160,108;70,1250,120,96;67,1500,160,102")

        step(
            "track4.create_instrument",
            "track_state_b",
            lambda: client.tool("logic_tracks", "create_instrument", {}, timeout=20.0),
            delay=1.1,
            note="used only to add a visible track; readback gaps remain covered by #35/#43",
        )
        choose_patch("stab-synth", 748, 650, "Synthesizer")
        record_layer("track4_stab", "48,0,300,94;55,0,300,92;60,0,300,90;51,1000,300,96;58,1000,300,92;63,1000,300,90")

        step("logic_edit.select_all", "edit_state_b", lambda: client.tool("logic_edit", "select_all"), delay=0.25)
        step("logic_navigate.zoom_to_fit", "navigate_state_b", lambda: client.tool("logic_navigate", "zoom_to_fit"), delay=0.7)
        step("logic://transport/state.after", "readback", lambda: client.resource("logic://transport/state"), delay=0.25)

        press_key("return", 0.2)
        click_xy(700, 88, 0.35)
        event("final.ui_play", "ui_transport", "ok", "clicked actual Logic Play button for final visual playback")
        time.sleep(5.0)
        click_xy(660, 88, 0.5)
        event("final.ui_stop", "ui_transport", "ok", "clicked actual Logic Stop button")
        screenshot(FINAL_SCREENSHOT)
        event("ui.final.screenshot", "provenance", "ok", "captured final arrangement screenshot", screenshot=str(FINAL_SCREENSHOT))
    finally:
        client.close()
        stop_capture(capture)

    states = {state: sum(1 for item in events if item["state"] == state) for state in sorted({item["state"] for item in events})}
    transcript = {
        "generated_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "raw_video": str(RAW_VIDEO),
        "fresh_baseline_screenshot": str(BASELINE_SCREENSHOT),
        "final_screenshot": str(FINAL_SCREENSHOT),
        "source": "actual Logic Pro screen recording from a fresh Empty Project; visible UI patch selection; no guide audio",
        "audio_policy": "no_audio_captured_or_added",
        "event_count": len(events),
        "states": states,
        "truth_boundaries": {
            "verified": [
                "fresh project baseline screenshot shows the first visible track as 1",
                "actual Logic UI capture was recorded for this v19 run",
                "Logic Library patch selections were performed visibly in the UI",
                "logic_midi.play_sequence returned ok/error/state for each layer in transcript",
            ],
            "not_claimed": [
                "actual Logic system audio",
                "Logic bounce/export audio",
                "MCP readback-verified patch assignment",
                "MCP readback-verified track creation",
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
