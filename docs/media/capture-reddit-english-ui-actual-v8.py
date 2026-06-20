#!/usr/bin/env python3
"""Capture a real English-UI Logic Pro MCP usage pass.

This script intentionally records the actual macOS/Logic screen. It does not
mock Logic's UI. The JSON transcript is captured from the same MCP process that
drives the visible actions.
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
RAW_VIDEO = Path("/tmp/logic-v8-english-ui-actual-raw.mp4")
TRANSCRIPT = ROOT / "docs/media/reddit-dudddee-english-ui-actual-v8-transcript.json"

FPS = 24


class MCPClient:
    def __init__(self) -> None:
        self.proc = subprocess.Popen(
            [str(BINARY)],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=open("/tmp/logic-v8-mcp-stderr.txt", "w"),
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

    def send(self, method: str, params: dict | None = None, timeout: float = 15.0) -> dict | None:
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

    def tool(self, name: str, command: str, params: dict | None = None, timeout: float = 15.0) -> dict | None:
        return self.send(
            "tools/call",
            {"name": name, "arguments": {"command": command, "params": params or {}}},
            timeout=timeout,
        )

    def resource(self, uri: str, timeout: float = 15.0) -> dict | None:
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
            verified = parsed.get("verified")
            reason = parsed.get("reason")
            return f"success=true verified={verified} reason={reason}"
        if "error" in parsed:
            return f"error={parsed.get('error')} hint={str(parsed.get('hint', ''))[:80]}"
        if "plugin_count" in parsed:
            return f"{parsed['plugin_count']} stock plugins cataloged"
        if "workflows" in parsed:
            return f"{len(parsed['workflows'])} workflow(s)"
        if "destinations" in parsed or "sources" in parsed:
            return f"{len(parsed.get('sources', []))} MIDI sources / {len(parsed.get('destinations', []))} destinations"
        if "data" in parsed:
            data = parsed["data"]
            if isinstance(data, list):
                return f"{len(data)} track(s) read"
            if isinstance(data, dict) and "state" in data:
                state = data["state"]
                return f"transport tempo={state.get('tempo')} playing={state.get('isPlaying')}"
    if text:
        return text.replace("\n", " ")[:120]
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


def click_stop_button() -> None:
    # Fallback for English Logic 12.2 when the AX stop button readback path is
    # unavailable. Coordinates are logical screen points on this MacBook display.
    subprocess.run(["/opt/homebrew/bin/cliclick", "c:620,87"], check=False)


def main() -> None:
    if not BINARY.exists():
        raise SystemExit(f"Missing MCP binary: {BINARY}")

    try:
        subprocess.run(
            ["osascript", "-e", 'tell application "Logic Pro" to activate'],
            check=False,
            timeout=3,
        )
    except subprocess.TimeoutExpired:
        pass
    time.sleep(1.0)

    capture = start_capture()
    events: list[dict] = []
    client = MCPClient()
    started_at = time.time()

    def step(label: str, kind: str, fn, delay: float = 1.25) -> dict | None:
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

    try:
        time.sleep(1.5)
        step("initialize", "session", lambda: client.send("initialize", {
            "protocolVersion": "2024-11-05",
            "capabilities": {},
            "clientInfo": {"name": "v8-english-ui-demo", "version": "1"},
        }))
        step("tools/list", "discovery", lambda: client.send("tools/list", {}))
        step("resources/list", "discovery", lambda: client.send("resources/list", {}))
        step("resources/templates/list", "discovery", lambda: client.send("resources/templates/list", {}))
        step("logic://system/health", "resource", lambda: client.resource("logic://system/health"))
        step("logic://midi/ports", "resource", lambda: client.resource("logic://midi/ports"))
        step("logic://stock-plugins/census", "resource", lambda: client.resource("logic://stock-plugins/census"))

        step("logic_tracks.create_instrument", "tool", lambda: client.tool("logic_tracks", "create_instrument"), delay=2.0)
        step("logic_transport.toggle_metronome", "tool", lambda: client.tool("logic_transport", "toggle_metronome"), delay=1.0)
        step("logic_transport.record", "tool", lambda: client.tool("logic_transport", "record"), delay=1.2)

        notes = "60,0,240,110;63,240,240,92;67,480,240,98;72,720,240,90;67,960,240,100;63,1200,240,90;60,1440,480,108"
        step("logic_midi.play_sequence", "tool", lambda: client.tool("logic_midi", "play_sequence", {"notes": notes}), delay=2.6)
        stop_response = step("logic_transport.stop", "tool", lambda: client.tool("logic_transport", "stop"), delay=0.4)
        if stop_response and stop_response.get("result", {}).get("isError"):
            click_stop_button()
            time.sleep(1.0)
            events.append({
                "label": "ui.stop_button_fallback",
                "kind": "ui",
                "start_s": round(time.time() - started_at, 3),
                "end_s": round(time.time() - started_at, 3),
                "summary": "clicked actual Logic Stop button after AX stop readback failed",
                "response": None,
            })

        step("logic_transport.play", "tool", lambda: client.tool("logic_transport", "play"), delay=3.0)
        step("logic_transport.stop.final", "tool", lambda: client.tool("logic_transport", "stop"), delay=1.0)
        step("logic://workflow-skills/search?query=bounce", "resource", lambda: client.resource("logic://workflow-skills/search?query=bounce"))
        time.sleep(1.5)
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
