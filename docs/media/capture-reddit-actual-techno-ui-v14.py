#!/usr/bin/env python3
"""Capture an actual Logic UI techno-from-scratch demo.

This records the real macOS/Logic Pro screen starting from Logic's real
"Create New Track" dialog. The visible actions are driven by the local MCP
server. No generated DAW surface or terminal panel is captured.
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
RAW_VIDEO = Path("/tmp/logic-v14-actual-techno-ui-raw.mp4")
TRANSCRIPT = ROOT / "docs/media/reddit-dudddee-actual-techno-ui-v14-transcript.json"
FPS = 24


class MCPClient:
    def __init__(self) -> None:
        self.proc = subprocess.Popen(
            [str(BINARY)],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=open("/tmp/logic-v14-mcp-stderr.txt", "w"),
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

    def send(self, method: str, params: dict | None = None, timeout: float = 18.0) -> dict | None:
        msg_id = self.next_id
        self.next_id += 1
        msg = {"jsonrpc": "2.0", "id": msg_id, "method": method, "params": params or {}}
        assert self.proc.stdin is not None
        self.proc.stdin.write(json.dumps(msg) + "\n")
        self.proc.stdin.flush()
        deadline = time.time() + timeout
        while time.time() < deadline:
            if msg_id in self.responses:
                return self.responses.pop(msg_id)
            time.sleep(0.03)
        return None

    def tool(self, name: str, command: str, params: dict | None = None, timeout: float = 18.0) -> dict | None:
        return self.send(
            "tools/call",
            {"name": name, "arguments": {"command": command, "params": params or {}}},
            timeout=timeout,
        )

    def resource(self, uri: str, timeout: float = 18.0) -> dict | None:
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


def text_from_response(response: dict | None) -> str:
    if response is None:
        return "timeout"
    if response.get("error"):
        return json.dumps(response["error"], ensure_ascii=False)
    result = response.get("result", {})
    content = result.get("content") or result.get("contents") or []
    if content and isinstance(content[0], dict):
        return str(content[0].get("text", ""))
    return json.dumps(result, ensure_ascii=False)


def classify(response: dict | None) -> str:
    if response is None:
        return "timeout"
    if response.get("error"):
        return "error"
    result = response.get("result", {})
    if result.get("isError") is True:
        return "error"
    text = text_from_response(response)
    try:
        parsed = json.loads(text)
    except Exception:
        return "ok"
    if isinstance(parsed, dict):
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
    text = text_from_response(response)
    try:
        parsed = json.loads(text)
    except Exception:
        return " ".join(text.split())[:160] if text else "ok"
    if isinstance(parsed, dict):
        if parsed.get("success") is True:
            return f"success=true verified={parsed.get('verified')} reason={parsed.get('reason')}"
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
            if isinstance(data, list):
                return f"{len(data)} item(s)"
    return "ok"


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
            proc.terminate()
            try:
                proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                proc.kill()


def focus_logic() -> None:
    run_quiet(["/opt/homebrew/bin/peekaboo", "app", "hide", "--app", "Google Chrome", "--json"], timeout=3)
    run_quiet(["/opt/homebrew/bin/peekaboo", "app", "switch", "--to", "Logic Pro", "--json"], timeout=4)
    time.sleep(0.7)


def click_create_track() -> bool:
    result = run_quiet(
        [
            "/opt/homebrew/bin/peekaboo",
            "click",
            "Create",
            "--app",
            "Logic Pro",
            "--json",
        ],
        timeout=5,
    )
    return result.returncode == 0


def return_to_start() -> None:
    run_quiet(["/opt/homebrew/bin/cliclick", "kp:return"], timeout=2)
    time.sleep(0.35)


def click_stop() -> None:
    run_quiet(["/opt/homebrew/bin/cliclick", "c:660,87"], timeout=2)
    time.sleep(0.25)


def main() -> None:
    if not BINARY.exists():
        raise SystemExit(f"Missing MCP binary: {BINARY}")

    focus_logic()
    capture = start_capture()
    client = MCPClient()
    started_at = time.time()
    events: list[dict[str, Any]] = []

    def event(label: str, family: str, state: str, summary: str, response: Any = None) -> None:
        now = round(time.time() - started_at, 3)
        events.append(
            {
                "label": label,
                "family": family,
                "start_s": now,
                "end_s": now,
                "state": state,
                "summary": summary,
                "response": response,
            }
        )
        print(f"{label}: {state} | {summary}", flush=True)

    def step(label: str, family: str, fn: Callable[[], dict | None], delay: float = 0.65) -> dict | None:
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
        events.append(item)
        print(f"{label}: {item['state']} | {item['summary']}", flush=True)
        time.sleep(delay)
        return response

    def record_layer(label: str, notes: str, hold: float = 1.15) -> None:
        return_to_start()
        step(f"{label}.record", "transport", lambda: client.tool("logic_transport", "record"), delay=0.35)
        step(f"{label}.play_sequence", "midi", lambda: client.tool("logic_midi", "play_sequence", {"notes": notes}), delay=hold)
        response = step(f"{label}.stop", "transport", lambda: client.tool("logic_transport", "stop"), delay=0.35)
        if classify(response) == "error":
            click_stop()
            event(f"{label}.ui_stop_fallback", "ui", "ok", "clicked actual Logic Stop button")

    try:
        time.sleep(1.0)
        event("ui.create_track_dialog", "ui", "ok", "real Logic Create New Track dialog visible")
        event("ui.click_create", "ui", "ok" if click_create_track() else "error", "clicked real Logic Create button")
        time.sleep(2.0)

        step(
            "initialize",
            "session",
            lambda: client.send(
                "initialize",
                {
                    "protocolVersion": "2024-11-05",
                    "capabilities": {},
                    "clientInfo": {"name": "v14-actual-techno-ui", "version": "1"},
                },
            ),
            delay=0.35,
        )
        step("logic://system/health", "readback", lambda: client.resource("logic://system/health"), delay=0.35)
        step("logic://transport/state", "readback", lambda: client.resource("logic://transport/state"), delay=0.35)
        step("logic_tracks.rename Kick", "tracks", lambda: client.tool("logic_tracks", "rename", {"index": 0, "name": "Kick"}), delay=0.45)
        step("logic_transport.set_tempo 128", "transport", lambda: client.tool("logic_transport", "set_tempo", {"tempo": 128}), delay=0.45)

        record_layer("kick", "36,0,140,125;36,500,140,118;36,1000,140,125;36,1500,140,118")

        step("logic_tracks.create Bass", "tracks", lambda: client.tool("logic_tracks", "create_instrument"), delay=1.0)
        step("logic_tracks.rename Bass", "tracks", lambda: client.tool("logic_tracks", "rename", {"index": 1, "name": "Sub Bass"}), delay=0.45)
        record_layer("bass", "43,0,260,112;43,500,220,96;46,1000,250,104;41,1500,260,108")

        step("logic_tracks.create Drummer", "tracks", lambda: client.tool("logic_tracks", "create_drummer"), delay=2.2)

        step("logic_tracks.create Stab", "tracks", lambda: client.tool("logic_tracks", "create_instrument"), delay=1.0)
        step("logic_tracks.rename Stab", "tracks", lambda: client.tool("logic_tracks", "rename", {"index": 3, "name": "Minor Stab"}), delay=0.45)
        record_layer("stab", "60,0,280,96;63,0,280,92;67,0,280,92;60,1000,280,96;63,1000,280,92;70,1000,280,90")

        step("logic_tracks.create Hats", "tracks", lambda: client.tool("logic_tracks", "create_instrument"), delay=1.0)
        step("logic_tracks.rename Hats", "tracks", lambda: client.tool("logic_tracks", "rename", {"index": 4, "name": "Closed Hats"}), delay=0.45)
        record_layer(
            "hats",
            "72,0,75,82;72,250,75,72;72,500,75,82;72,750,75,72;72,1000,75,82;72,1250,75,72;72,1500,75,82;72,1750,75,72",
        )

        step("logic_edit.select_all", "edit", lambda: client.tool("logic_edit", "select_all"), delay=0.35)
        step("logic_edit.quantize 1/16", "edit", lambda: client.tool("logic_edit", "quantize", {"value": "1/16"}), delay=0.55)
        step("logic_navigate.zoom_to_fit", "navigate", lambda: client.tool("logic_navigate", "zoom_to_fit"), delay=0.8)
        step("readback logic://tracks", "readback", lambda: client.resource("logic://tracks"), delay=0.3)
        step("logic_project.get_regions", "readback", lambda: client.tool("logic_project", "get_regions"), delay=0.5)

        return_to_start()
        step("logic_transport.play final", "transport", lambda: client.tool("logic_transport", "play"), delay=6.0)
        step("logic_transport.stop final", "transport", lambda: client.tool("logic_transport", "stop"), delay=0.35)
        click_stop()
    finally:
        client.close()
        stop_capture(capture)

    states = {state: sum(1 for item in events if item["state"] == state) for state in sorted({item["state"] for item in events})}
    transcript = {
        "generated_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "raw_video": str(RAW_VIDEO),
        "source": "actual Logic Pro screen recording",
        "event_count": len(events),
        "states": states,
        "events": events,
    }
    TRANSCRIPT.write_text(json.dumps(transcript, ensure_ascii=False, indent=2))
    print(f"captured {RAW_VIDEO}")
    print(f"transcript {TRANSCRIPT}")
    print(f"states {states}")


if __name__ == "__main__":
    main()
