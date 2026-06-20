#!/usr/bin/env python3
"""Continue the real Logic UI techno demo from the visible Logic session."""

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
RAW_VIDEO = Path("/tmp/logic-v16-actual-techno-ui-raw.mp4")
TRANSCRIPT = ROOT / "docs/media/reddit-dudddee-actual-techno-ui-v16-transcript.json"
FPS = 24


class MCPClient:
    def __init__(self) -> None:
        self.proc = subprocess.Popen(
            [str(BINARY)],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=open("/tmp/logic-v16-mcp-stderr.txt", "w"),
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
        assert self.proc.stdin is not None
        self.proc.stdin.write(json.dumps({"jsonrpc": "2.0", "id": msg_id, "method": method, "params": params or {}}) + "\n")
        self.proc.stdin.flush()
        deadline = time.time() + timeout
        while time.time() < deadline:
            if msg_id in self.responses:
                return self.responses.pop(msg_id)
            time.sleep(0.03)
        return None

    def tool(self, name: str, command: str, params: dict | None = None, timeout: float = 18.0) -> dict | None:
        return self.send("tools/call", {"name": name, "arguments": {"command": command, "params": params or {}}}, timeout=timeout)

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


def classify(response: dict | None) -> str:
    if response is None:
        return "timeout"
    if response.get("error") or response.get("result", {}).get("isError") is True:
        return "error"
    try:
        parsed = json.loads(parse_text(response))
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
    text = parse_text(response)
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
            if isinstance(data, list):
                return f"{len(data)} item(s)"
            if isinstance(data, dict) and "state" in data:
                state = data["state"]
                return f"transport tempo={state.get('tempo')} playing={state.get('isPlaying')}"
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
            proc.kill()


def click_xy(x: int, y: int, delay: float = 0.4) -> bool:
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
    capture = start_capture()
    client = MCPClient()
    started_at = time.time()
    events: list[dict[str, Any]] = []

    def event(label: str, family: str, state: str, summary: str, response: Any = None) -> None:
        now = round(time.time() - started_at, 3)
        events.append({"label": label, "family": family, "start_s": now, "end_s": now, "state": state, "summary": summary, "response": response})
        print(f"{label}: {state} | {summary}", flush=True)

    def step(label: str, family: str, fn: Callable[[], dict | None], delay: float = 0.55) -> dict | None:
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

    def choose_patch(label: str, category_y: int, preset_y: int) -> None:
        click_xy(80, category_y, 0.35)
        click_xy(275, preset_y, 1.5)
        event(f"ui.patch.{label}", "ui", "ok", f"selected visible Logic Library patch for {label}")

    def record_layer(label: str, notes: str, hold: float = 1.6) -> None:
        press_key("return", 0.25)
        click_xy(740, 88, 0.55)
        event(f"{label}.ui_record", "ui", "ok", "clicked actual Logic Record button")
        step(f"{label}.play_sequence", "midi", lambda: client.tool("logic_midi", "play_sequence", {"notes": notes}), delay=hold)
        click_xy(660, 88, 0.7)
        event(f"{label}.ui_stop", "ui", "ok", "clicked actual Logic Stop button")

    try:
        time.sleep(1.0)
        step(
            "initialize",
            "session",
            lambda: client.send(
                "initialize",
                {
                    "protocolVersion": "2024-11-05",
                    "capabilities": {},
                    "clientInfo": {"name": "v16-actual-techno-ui", "version": "1"},
                },
            ),
            delay=0.3,
        )
        step("tools/list", "discovery", lambda: client.send("tools/list"), delay=0.3)
        step("logic://system/health", "readback", lambda: client.resource("logic://system/health"), delay=0.3)
        step("logic://transport/state", "readback", lambda: client.resource("logic://transport/state"), delay=0.3)

        click_xy(720, 315, 0.35)
        choose_patch("bass-or-percussion-foundation", 428, 575)
        record_layer("bass", "43,0,260,112;43,500,220,96;46,1000,250,104;41,1500,260,108")

        step("logic_tracks.create_instrument lead", "tracks", lambda: client.tool("logic_tracks", "create_instrument"), delay=1.3)
        choose_patch("synth-stab", 748, 552)
        record_layer("stab", "60,0,280,96;63,0,280,92;67,0,280,92;60,1000,280,96;63,1000,280,92;70,1000,280,90")

        step("logic_tracks.create_drummer", "tracks", lambda: client.tool("logic_tracks", "create_drummer"), delay=1.6)
        step("logic_edit.select_all", "edit", lambda: client.tool("logic_edit", "select_all"), delay=0.35)
        step("logic_edit.quantize 1/16", "edit", lambda: client.tool("logic_edit", "quantize", {"value": "1/16"}), delay=0.55)
        step("logic_navigate.zoom_to_fit", "navigate", lambda: client.tool("logic_navigate", "zoom_to_fit"), delay=0.8)
        step("logic://transport/state final readback", "readback", lambda: client.resource("logic://transport/state"), delay=0.3)

        press_key("return", 0.2)
        click_xy(700, 88, 0.4)
        event("final.ui_play", "ui", "ok", "clicked actual Logic Play button for final playback")
        time.sleep(5.0)
        click_xy(660, 88, 0.5)
        event("final.ui_stop", "ui", "ok", "clicked actual Logic Stop button")
    finally:
        client.close()
        stop_capture(capture)

    states = {state: sum(1 for item in events if item["state"] == state) for state in sorted({item["state"] for item in events})}
    transcript = {
        "generated_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "raw_video": str(RAW_VIDEO),
        "source": "actual Logic Pro screen recording; UI transport clicks used because #47/#48 are filed product issues",
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
