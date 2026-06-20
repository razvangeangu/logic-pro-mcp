#!/usr/bin/env python3
"""Capture a richer techno composition being assembled in the real Logic UI."""

from __future__ import annotations

import json
import importlib.util
import signal
import subprocess
import sys
import threading
import time
from pathlib import Path
from typing import Any, Callable


ROOT = Path(__file__).resolve().parents[2]
BINARY = ROOT / ".build/release/LogicProMCP"
SOURCE = ROOT / "artifacts/acid-track-composition-v4"
LAYER_SPECS = SOURCE / "v4-layer-specs.json"
COMPOSER = SOURCE / "make_v4_composition.py"
RAW_VIDEO = Path("/tmp/logic-v17-rich-techno-ui-raw.mp4")
TRANSCRIPT = ROOT / "docs/media/reddit-dudddee-rich-techno-ui-v17-transcript.json"
FPS = 24
LIVE_RECORD_WINDOW_MS = 7_600
MAX_PLAY_SEQUENCE_EVENTS = 240


class MCPClient:
    def __init__(self) -> None:
        self.proc = subprocess.Popen(
            [str(BINARY)],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=open("/tmp/logic-v17-mcp-stderr.txt", "w"),
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

    def send(self, method: str, params: dict | None = None, timeout: float = 45.0) -> dict | None:
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

    def tool(self, name: str, command: str, params: dict | None = None, timeout: float = 45.0) -> dict | None:
        return self.send("tools/call", {"name": name, "arguments": {"command": command, "params": params or {}}}, timeout=timeout)

    def resource(self, uri: str, timeout: float = 30.0) -> dict | None:
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
    if "resources" in result:
        return f"{len(result['resources'])} resources"
    parsed = payload(response)
    if parsed:
        if parsed.get("success") is True:
            bits = [f"success=true verified={parsed.get('verified')}"]
            for key in ("observed_delta", "track_count_after", "created_track", "note_count", "method", "path", "reason"):
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
        if "data" in parsed:
            data = parsed["data"]
            if isinstance(data, dict) and "state" in data:
                state = data["state"]
                return f"transport tempo={state.get('tempo')} playing={state.get('isPlaying')}"
    text = parse_text(response)
    return " ".join(text.split())[:180] if text else "ok"


def run_quiet(args: list[str], timeout: float | None = None) -> subprocess.CompletedProcess:
    return subprocess.run(args, check=False, timeout=timeout, text=True, capture_output=True)


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


def load_composer() -> Any:
    spec = importlib.util.spec_from_file_location("v17_rich_composer", COMPOSER)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Cannot load {COMPOSER}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def load_layers() -> list[dict[str, Any]]:
    raw = json.loads(LAYER_SPECS.read_text(encoding="utf-8"))
    parts = {part.name: part for part in load_composer().build_parts()}
    layers: list[dict[str, Any]] = []
    for item in raw:
        part = parts[item["name"]]
        first_offset = min(event.offset_ms() for event in part.events)
        live_events = [
            event for event in part.events
            if first_offset <= event.offset_ms() <= first_offset + LIVE_RECORD_WINDOW_MS
        ][:MAX_PLAY_SEQUENCE_EVENTS]
        live_specs: list[str] = []
        live_duration_ms = 0
        for event in live_events:
            offset = event.offset_ms() - first_offset
            duration = event.duration_ms()
            live_duration_ms = max(live_duration_ms, offset + duration)
            live_specs.append(f"{event.pitch},{offset},{duration},{event.velocity},{event.channel}")
        next_item = dict(item)
        next_item["notes_spec"] = ";".join(live_specs)
        next_item["live_note_count"] = len(live_events)
        next_item["live_duration_s"] = max(1.0, live_duration_ms / 1000.0)
        next_item["source_first_offset_ms"] = first_offset
        layers.append(next_item)
    return layers


def main() -> None:
    if not BINARY.exists():
        raise SystemExit(f"Missing MCP binary: {BINARY}")
    if not LAYER_SPECS.exists():
        raise SystemExit(f"Missing layer specs: {LAYER_SPECS}")

    layers = load_layers()
    focus_logic()
    click_xy(1130, 335, 0.2)
    press_key("e", 0.4)  # Close the editor if it is open, giving the arrange area more vertical space.
    capture = start_capture()
    client = MCPClient()
    started_at = time.time()
    events: list[dict[str, Any]] = []

    def event(label: str, family: str, state: str, summary: str, response: Any = None, **extra: Any) -> None:
        now = round(time.time() - started_at, 3)
        item = {"label": label, "family": family, "start_s": now, "end_s": now, "state": state, "summary": summary, "response": response}
        item.update(extra)
        events.append(item)
        print(f"{label}: {state} | {summary}", flush=True)

    def step(label: str, family: str, fn: Callable[[], dict | None], delay: float = 0.55, **extra: Any) -> dict | None:
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

    try:
        time.sleep(0.8)
        step(
            "initialize",
            "session",
            lambda: client.send(
                "initialize",
                {
                    "protocolVersion": "2024-11-05",
                    "capabilities": {},
                    "clientInfo": {"name": "v17-rich-techno-ui", "version": "1"},
                },
            ),
            delay=0.25,
        )
        step("tools/list", "discovery", lambda: client.send("tools/list"), delay=0.25)
        step("logic://system/health", "readback", lambda: client.resource("logic://system/health"), delay=0.25)
        step("logic://transport/state.before", "readback", lambda: client.resource("logic://transport/state"), delay=0.25)
        event(
            "recording.path",
            "composition",
            "ok",
            "using actual Logic record + logic_midi.play_sequence because import_file is blocked by #49 and record_sequence is covered by #42",
        )

        imported: list[dict[str, Any]] = []
        for number, layer in enumerate(layers, start=1):
            name = layer["name"]
            step(
                f"track.create.{name}",
                "track",
                lambda: client.tool("logic_tracks", "create_instrument", {}, timeout=20.0),
                delay=0.65,
                layer_name=name,
                role=layer["role"],
                layer_number=number,
            )
            press_key("return", 0.2)
            click_xy(740, 88, 0.35)
            event(f"ui_record.{name}", "ui", "ok", "clicked actual Logic Record button before sending MIDI", layer_name=name)
            response = step(
                f"play_sequence.{name}",
                "midi_live_record",
                lambda notes=layer["notes_spec"]: client.tool(
                    "logic_midi",
                    "play_sequence",
                    {"notes": notes},
                    timeout=20.0,
                ),
                delay=0.2,
                layer_name=name,
                role=layer["role"],
                patch=layer["patch"],
                note_count=layer["live_note_count"],
                source_note_count=layer["note_count"],
                live_duration_s=layer["live_duration_s"],
                layer_number=number,
            )
            time.sleep(layer["live_duration_s"] + 0.65)
            click_xy(660, 88, 0.35)
            event(f"ui_stop.{name}", "ui", "ok", "clicked actual Logic Stop button after live MIDI recording", layer_name=name)
            parsed = parse_text(response)
            imported.append({
                "name": name,
                "patch": layer["patch"],
                "live_note_count": layer["live_note_count"],
                "source_note_count": layer["note_count"],
                "mcp_response": parsed,
            })

            # Create a little visual separation every few layers so the arrangement
            # remains readable during the long live-recording capture.
            if number in (4, 8):
                step("logic_navigate.zoom_to_fit.partial", "navigate", lambda: client.tool("logic_navigate", "zoom_to_fit"), delay=0.5)

        step("logic_edit.select_all", "edit", lambda: client.tool("logic_edit", "select_all"), delay=0.25)
        step("logic_navigate.zoom_to_fit", "navigate", lambda: client.tool("logic_navigate", "zoom_to_fit"), delay=0.8)
        step("logic://transport/state.after", "readback", lambda: client.resource("logic://transport/state"), delay=0.25)

        press_key("return", 0.2)
        click_xy(700, 88, 0.35)
        event("final.ui_play", "ui", "ok", "clicked actual Logic Play button for final playback")
        time.sleep(8.0)
        click_xy(660, 88, 0.4)
        event("final.ui_stop", "ui", "ok", "clicked actual Logic Stop button")
    finally:
        client.close()
        stop_capture(capture)

    states = {state: sum(1 for item in events if item["state"] == state) for state in sorted({item["state"] for item in events})}
    transcript = {
        "generated_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "raw_video": str(RAW_VIDEO),
        "source": "actual Logic Pro screen recording; MIDI layers use actual Logic recording plus logic_midi.play_sequence because logic_midi.import_file is blocked by #49 and logic_tracks.record_sequence remains #42; final audio is rendered as a guide track in post",
        "tempo_bpm": 120.0,
        "composition_source": str(SOURCE),
        "layer_count": len(layers),
        "event_count": len(events),
        "states": states,
        "imported": imported,
        "layers": layers,
        "events": events,
    }
    TRANSCRIPT.write_text(json.dumps(transcript, ensure_ascii=False, indent=2))
    print(f"captured {RAW_VIDEO}")
    print(f"transcript {TRANSCRIPT}")
    print(f"states {states}")


if __name__ == "__main__":
    main()
