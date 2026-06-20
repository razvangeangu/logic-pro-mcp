#!/usr/bin/env python3
"""Record a cleaner real Logic Pro English-UI usage pass.

The capture is the actual macOS/Logic screen. No fake Logic UI is rendered.
The MCP transcript is captured from the same server process that drives the
visible actions in Logic.
"""

from __future__ import annotations

import json
import signal
import subprocess
import threading
import time
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
BINARY = ROOT / ".build/release/LogicProMCP"
RAW_VIDEO = Path("/tmp/logic-v9-english-ui-actual-raw.mp4")
TRANSCRIPT = ROOT / "docs/media/reddit-dudddee-english-ui-actual-v9-transcript.json"
FPS = 24


class MCPClient:
    def __init__(self) -> None:
        self.proc = subprocess.Popen(
            [str(BINARY)],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=open("/tmp/logic-v9-mcp-stderr.txt", "w"),
            text=True,
            bufsize=0,
        )
        self.responses: dict[int, dict] = {}
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

    def send(self, method: str, params: dict | None = None, timeout: float = 12.0) -> dict | None:
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

    def tool(self, name: str, command: str, params: dict | None = None, timeout: float = 12.0) -> dict | None:
        return self.send(
            "tools/call",
            {"name": name, "arguments": {"command": command, "params": params or {}}},
            timeout=timeout,
        )

    def resource(self, uri: str, timeout: float = 12.0) -> dict | None:
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


def summarize(response: dict | None) -> str:
    if response is None:
        return "timeout"
    if "error" in response:
        return f"jsonrpc_error={response['error']}"
    result = response.get("result", {})
    if "tools" in result:
        return f"{len(result['tools'])} tools exposed"
    if "resources" in result:
        return f"{len(result['resources'])} resources visible"
    if "resourceTemplates" in result:
        return f"{len(result['resourceTemplates'])} resource templates visible"
    content = result.get("content") or result.get("contents") or []
    text = content[0].get("text", "") if content else ""
    try:
        parsed = json.loads(text)
    except Exception:
        parsed = None
    if isinstance(parsed, dict):
        if parsed.get("success") is True:
            return f"success=true verified={parsed.get('verified')} reason={parsed.get('reason')}"
        if "error" in parsed:
            return f"error={parsed.get('error')}"
        if "plugin_count" in parsed:
            return f"{parsed['plugin_count']} stock plugins cataloged"
        if "workflows" in parsed:
            return f"{len(parsed['workflows'])} workflow(s)"
        if "destinations" in parsed or "sources" in parsed:
            return f"{len(parsed.get('sources', []))} MIDI sources / {len(parsed.get('destinations', []))} destinations"
    if text:
        return text.replace("\n", " ")[:140]
    return "ok"


def start_capture() -> subprocess.Popen:
    cmd = [
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
    ]
    return subprocess.Popen(cmd, stdin=subprocess.PIPE)


def activate_logic() -> None:
    try:
        subprocess.run(
            ["osascript", "-e", 'tell application "Logic Pro" to activate'],
            check=False,
            timeout=3,
        )
    except subprocess.TimeoutExpired:
        pass
    time.sleep(0.7)


def key_return_to_start() -> None:
    subprocess.run(["/opt/homebrew/bin/cliclick", "kp:return"], check=False)
    time.sleep(0.4)


def click_stop_button() -> None:
    subprocess.run(["/opt/homebrew/bin/cliclick", "c:620,87"], check=False)
    time.sleep(0.3)


def main() -> None:
    if not BINARY.exists():
        raise SystemExit(f"Missing MCP binary: {BINARY}")

    activate_logic()
    capture = start_capture()
    client = MCPClient()
    events: list[dict] = []
    started_at = time.time()

    def step(label: str, kind: str, fn, delay: float = 0.85) -> dict | None:
        t0 = time.time() - started_at
        response = fn()
        t1 = time.time() - started_at
        event = {
            "label": label,
            "kind": kind,
            "start_s": round(t0, 3),
            "end_s": round(t1, 3),
            "summary": summarize(response),
            "response": response,
        }
        events.append(event)
        print(f"{label}: {event['summary']}", flush=True)
        time.sleep(delay)
        return response

    def record_region(label: str, notes: str, after: float = 1.2) -> None:
        key_return_to_start()
        step(f"{label}.record", "tool", lambda: client.tool("logic_transport", "record"), delay=0.45)
        step(f"{label}.play_sequence", "tool", lambda: client.tool("logic_midi", "play_sequence", {"notes": notes}), delay=after)
        response = step(f"{label}.stop", "tool", lambda: client.tool("logic_transport", "stop"), delay=0.35)
        if response and response.get("result", {}).get("isError"):
            click_stop_button()
            events.append({
                "label": f"{label}.ui_stop_fallback",
                "kind": "ui",
                "start_s": round(time.time() - started_at, 3),
                "end_s": round(time.time() - started_at, 3),
                "summary": "clicked actual Logic Stop button",
                "response": None,
            })

    try:
        time.sleep(1.0)
        step("initialize", "session", lambda: client.send("initialize", {
            "protocolVersion": "2024-11-05",
            "capabilities": {},
            "clientInfo": {"name": "v9-english-ui-real-demo", "version": "1"},
        }))
        step("tools/list", "discovery", lambda: client.send("tools/list", {}), delay=0.45)
        step("resources/list", "discovery", lambda: client.send("resources/list", {}), delay=0.45)
        step("resources/templates/list", "discovery", lambda: client.send("resources/templates/list", {}), delay=0.45)
        step("logic://system/health", "resource", lambda: client.resource("logic://system/health"), delay=0.45)
        step("logic://midi/ports", "resource", lambda: client.resource("logic://midi/ports"), delay=0.45)
        step("logic://stock-plugins/census", "resource", lambda: client.resource("logic://stock-plugins/census"), delay=0.7)

        step("logic_tracks.rename Kick", "tool", lambda: client.tool("logic_tracks", "rename", {"index": 0, "name": "Kick"}), delay=1.0)
        record_region(
            "kick",
            "36,0,160,122;36,500,160,118;36,1000,160,122;36,1500,160,118",
            after=1.0,
        )

        step("logic_tracks.create Bass", "tool", lambda: client.tool("logic_tracks", "create_instrument"), delay=0.8)
        step("logic_tracks.rename Bass", "tool", lambda: client.tool("logic_tracks", "rename", {"index": 1, "name": "Bass"}), delay=0.8)
        record_region(
            "bass",
            "43,0,240,110;43,500,220,94;46,1000,240,104;41,1500,260,108",
            after=1.0,
        )

        step("logic_tracks.create Stab", "tool", lambda: client.tool("logic_tracks", "create_instrument"), delay=0.8)
        step("logic_tracks.rename Stab", "tool", lambda: client.tool("logic_tracks", "rename", {"index": 2, "name": "Stab"}), delay=0.8)
        record_region(
            "stab",
            "60,0,280,94;63,0,280,92;67,0,280,92;60,1000,280,94;63,1000,280,92;70,1000,280,90",
            after=1.0,
        )

        step("logic_tracks.create Hat", "tool", lambda: client.tool("logic_tracks", "create_instrument"), delay=0.8)
        step("logic_tracks.rename Hat", "tool", lambda: client.tool("logic_tracks", "rename", {"index": 3, "name": "Hat"}), delay=0.8)
        record_region(
            "hat",
            "72,0,80,82;72,250,80,74;72,500,80,82;72,750,80,74;72,1000,80,82;72,1250,80,74;72,1500,80,82;72,1750,80,74",
            after=1.0,
        )

        step("logic_navigate.zoom_to_fit", "tool", lambda: client.tool("logic_navigate", "zoom_to_fit"), delay=0.9)
        key_return_to_start()
        step("logic_transport.play final", "tool", lambda: client.tool("logic_transport", "play"), delay=5.0)
        step("logic_transport.stop final", "tool", lambda: client.tool("logic_transport", "stop"), delay=0.7)
        step("logic://workflow-skills/search?query=bounce", "resource", lambda: client.resource("logic://workflow-skills/search?query=bounce"), delay=0.8)
    finally:
        client.close()
        if capture.stdin:
            try:
                capture.stdin.write(b"q")
                capture.stdin.flush()
            except Exception:
                pass
        try:
            capture.wait(timeout=10)
        except subprocess.TimeoutExpired:
            capture.send_signal(signal.SIGINT)
            try:
                capture.wait(timeout=15)
            except subprocess.TimeoutExpired:
                capture.terminate()
                try:
                    capture.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    capture.kill()

    transcript = {
        "generated_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "raw_video": str(RAW_VIDEO),
        "logic_language": "English via com.apple.logic10 AppleLanguages=[en]",
        "events": events,
    }
    TRANSCRIPT.write_text(json.dumps(transcript, ensure_ascii=False, indent=2))
    print(f"captured {RAW_VIDEO}")
    print(f"transcript {TRANSCRIPT}")


if __name__ == "__main__":
    main()
