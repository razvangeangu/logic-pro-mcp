#!/usr/bin/env python3
"""Capture a real QA-driven Logic Pro MCP demo with varied track types.

This records the actual Logic Pro UI while a single MCP stdio session exercises
read surfaces, mutating commands, MIDI playback, track-type creation, navigation,
plugin inventory, and safety/error paths. The transcript is the source for the
final captions; failed or unverified operations are kept instead of hidden.
"""

from __future__ import annotations

import json
import signal
import subprocess
import threading
import time
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[2]
BINARY = ROOT / ".build/release/LogicProMCP"
RAW_VIDEO = Path("/tmp/logic-v11-varied-track-types-raw.mp4")
TRANSCRIPT = ROOT / "docs/media/reddit-dudddee-varied-track-types-v11-transcript.json"

FPS = 24


class MCPClient:
    def __init__(self) -> None:
        self.proc = subprocess.Popen(
            [str(BINARY)],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=open("/tmp/logic-v10-mcp-stderr.txt", "w"),
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


def parse_text(response: dict | None) -> str:
    if response is None:
        return "timeout"
    if "error" in response:
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
    text = parse_text(response)
    try:
        parsed = json.loads(text)
    except Exception:
        parsed = None
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
    if "error" in response:
        return f"jsonrpc error: {response['error']}"
    result = response.get("result", {})
    if "tools" in result:
        return f"{len(result['tools'])} MCP tools exposed"
    if "resources" in result:
        return f"{len(result['resources'])} resources exposed"
    if "resourceTemplates" in result:
        return f"{len(result['resourceTemplates'])} templates exposed"

    text = parse_text(response)
    try:
        parsed = json.loads(text)
    except Exception:
        parsed = None
    if isinstance(parsed, dict):
        if parsed.get("success") is True:
            return f"success=true verified={parsed.get('verified')} reason={parsed.get('reason')}"
        if parsed.get("error"):
            return f"error={parsed.get('error')} hint={str(parsed.get('hint', ''))[:70]}"
        if "channels" in parsed:
            channels = parsed.get("channels", {})
            channel_values = channels.values() if isinstance(channels, dict) else channels
            ready = sum(1 for channel in channel_values if isinstance(channel, dict) and channel.get("ready"))
            total = len(channels)
            return f"health {ready}/{total} channels ready"
        if "plugin_count" in parsed:
            return f"{parsed['plugin_count']} stock plugins cataloged"
        if "entries" in parsed:
            return f"{len(parsed['entries'])} catalog result(s)"
        if "workflows" in parsed:
            return f"{len(parsed['workflows'])} workflow skill(s)"
        if "destinations" in parsed or "sources" in parsed:
            return f"{len(parsed.get('sources', []))} MIDI sources / {len(parsed.get('destinations', []))} destinations"
        if "strips" in parsed:
            return f"{len(parsed.get('strips', []))} mixer strip(s)"
        if "data" in parsed:
            data = parsed["data"]
            if isinstance(data, list):
                return f"{len(data)} item(s) read"
            if isinstance(data, dict):
                if "tempo" in data:
                    return f"project tempo={data.get('tempo')} sampleRate={data.get('sampleRate')}"
                if "state" in data:
                    state = data["state"]
                    return f"transport tempo={state.get('tempo')} playing={state.get('isPlaying')}"
    clean = " ".join(text.split())
    return clean[:140] if clean else "ok"


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


def activate_logic() -> None:
    try:
        subprocess.run(["osascript", "-e", 'tell application "Logic Pro" to activate'], check=False, timeout=3)
    except subprocess.TimeoutExpired:
        pass
    time.sleep(0.8)
    try:
        subprocess.run(
            [
                "osascript",
                "-e",
                'tell application "Logic Pro" to set bounds of front window to {0, 30, 3840, 2070}',
            ],
            check=False,
            timeout=3,
        )
    except subprocess.TimeoutExpired:
        pass
    time.sleep(0.5)


def return_to_start() -> None:
    subprocess.run(["/opt/homebrew/bin/cliclick", "kp:return"], check=False)
    time.sleep(0.35)


def click_stop() -> None:
    subprocess.run(["/opt/homebrew/bin/cliclick", "c:660,87"], check=False)
    time.sleep(0.3)


def confirm_track_dialog() -> None:
    # Logic's track-type key commands can leave the Create New Track dialog open.
    # Click the dialog's Create button in screen-point coordinates. If no dialog
    # is open, this lands in the arrange area and is harmless.
    subprocess.run(["/opt/homebrew/bin/cliclick", "c:1370,672"], check=False)
    time.sleep(1.0)


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


def main() -> None:
    if not BINARY.exists():
        raise SystemExit(f"Missing MCP binary: {BINARY}")

    activate_logic()
    capture = start_capture()
    client = MCPClient()
    started_at = time.time()
    events: list[dict[str, Any]] = []

    def step(label: str, family: str, fn, delay: float = 0.7, timeout: float | None = None) -> dict | None:
        t0 = time.time() - started_at
        if timeout is None:
            response = fn()
        else:
            response = fn(timeout)
        t1 = time.time() - started_at
        event = {
            "label": label,
            "family": family,
            "start_s": round(t0, 3),
            "end_s": round(t1, 3),
            "state": classify(response),
            "summary": compact(response),
            "response": response,
        }
        events.append(event)
        print(f"{label}: {event['state']} | {event['summary']}", flush=True)
        time.sleep(delay)
        return response

    def record_layer(label: str, notes: str, delay_after_sequence: float = 0.9) -> None:
        return_to_start()
        step(f"{label}.record", "transport", lambda: client.tool("logic_transport", "record"), delay=0.35)
        step(f"{label}.play_sequence", "midi", lambda: client.tool("logic_midi", "play_sequence", {"notes": notes}), delay=delay_after_sequence)
        response = step(f"{label}.stop", "transport", lambda: client.tool("logic_transport", "stop"), delay=0.3)
        if classify(response) == "error":
            click_stop()
            events.append(
                {
                    "label": f"{label}.ui_stop_fallback",
                    "family": "ui",
                    "start_s": round(time.time() - started_at, 3),
                    "end_s": round(time.time() - started_at, 3),
                    "state": "ok",
                    "summary": "clicked actual Logic Stop button",
                    "response": None,
                }
            )

    try:
        time.sleep(1.0)
        step("initialize", "session", lambda: client.send("initialize", {
            "protocolVersion": "2024-11-05",
            "capabilities": {},
            "clientInfo": {"name": "v11-varied-track-types-demo", "version": "1"},
        }), delay=0.4)

        step("tools/list", "discovery", lambda: client.send("tools/list", {}), delay=0.25)
        step("resources/list", "discovery", lambda: client.send("resources/list", {}), delay=0.25)
        step("resources/templates/list", "discovery", lambda: client.send("resources/templates/list", {}), delay=0.25)

        for uri in [
            "logic://system/health",
            "logic://project/info",
            "logic://transport/state",
            "logic://tracks",
            "logic://mixer",
            "logic://markers",
            "logic://midi/ports",
            "logic://stock-plugins/census",
            "logic://stock-plugins/capabilities",
            "logic://workflow-skills/schema",
            "logic://stock-plugins/search?query=Gain",
            "logic://workflow-skills/search?query=session",
        ]:
            step(uri, "resource", lambda uri=uri: client.resource(uri), delay=0.25)

        for command in ["health", "permissions", "refresh_cache", "help"]:
            step(f"logic_system.{command}", "system", lambda command=command: client.tool("logic_system", command), delay=0.2)

        step("logic_transport.set_tempo 128.0", "transport", lambda: client.tool("logic_transport", "set_tempo", {"tempo": 128.0}), delay=0.6)
        step("logic_transport.toggle_metronome", "transport", lambda: client.tool("logic_transport", "toggle_metronome"), delay=0.5)
        step("logic_transport.toggle_cycle", "transport", lambda: client.tool("logic_transport", "toggle_cycle"), delay=0.4)
        step("logic_navigate.create_marker QA start", "navigate", lambda: client.tool("logic_navigate", "create_marker", {"name": "QA start"}), delay=0.6)

        # Exercise direct MIDI send commands before recording full regions.
        for label, params in [
            ("send_note C3", {"note": 48, "velocity": 100, "duration_ms": 90}),
            ("send_chord Cm", {"notes": "48,51,55", "duration_ms": 120}),
            ("send_cc mod", {"controller": 1, "value": 64}),
            ("send_program_change", {"program": 0}),
            ("send_pitch_bend", {"value": 8192}),
            ("send_aftertouch", {"value": 80}),
        ]:
            command = label.split()[0]
            step(f"logic_midi.{label}", "midi", lambda command=command, params=params: client.tool("logic_midi", command, params), delay=0.18)

        record_layer(
            "software_instrument_phrase",
            "48,0,300,104;51,500,260,96;55,1000,300,102;58,1500,300,94;60,2000,450,108",
            0.9,
        )
        step("logic_tracks.create Drummer / Session Player", "tracks", lambda: client.tool("logic_tracks", "create_drummer"), delay=0.4)
        confirm_track_dialog()
        events.append({
            "label": "ui.confirm Drummer track dialog",
            "family": "ui",
            "start_s": round(time.time() - started_at, 3),
            "end_s": round(time.time() - started_at, 3),
            "state": "ok",
            "summary": "pressed Create in Logic's New Track dialog when present",
            "response": None,
        })
        step("logic_tracks.create Audio track", "tracks", lambda: client.tool("logic_tracks", "create_audio"), delay=0.4)
        confirm_track_dialog()
        events.append({
            "label": "ui.confirm Audio track dialog",
            "family": "ui",
            "start_s": round(time.time() - started_at, 3),
            "end_s": round(time.time() - started_at, 3),
            "state": "ok",
            "summary": "pressed Create in Logic's New Track dialog when present",
            "response": None,
        })
        step("logic_tracks.create External MIDI track", "tracks", lambda: client.tool("logic_tracks", "create_external_midi"), delay=0.4)
        confirm_track_dialog()
        events.append({
            "label": "ui.confirm External MIDI track dialog",
            "family": "ui",
            "start_s": round(time.time() - started_at, 3),
            "end_s": round(time.time() - started_at, 3),
            "state": "ok",
            "summary": "pressed Create in Logic's New Track dialog when present",
            "response": None,
        })

        # Exercise the MIDI surface on the newly-created external MIDI context.
        for label, params in [
            ("send_program_change piano", {"program": 0}),
            ("send_note external C2", {"note": 36, "velocity": 96, "duration_ms": 120}),
            ("send_cc external volume", {"controller": 7, "value": 100}),
            ("send_pitch_bend external center", {"value": 8192}),
        ]:
            command = label.split()[0]
            step(f"logic_midi.{label}", "midi", lambda command=command, params=params: client.tool("logic_midi", command, params), delay=0.2)

        # Mixer writes are honestly gated on MCU feedback. Exercise one volume
        # and one pan call so the QA transcript shows the current machine state
        # without drowning the demo in repeated dependency failures.
        step("logic_mixer.set_volume track 0", "mixer", lambda: client.tool("logic_mixer", "set_volume", {"track": 0, "value": 0.82}), delay=0.3)
        step("logic_mixer.set_pan track 0", "mixer", lambda: client.tool("logic_mixer", "set_pan", {"track": 0, "value": -0.05}), delay=0.3)

        step("logic_edit.select_all", "edit", lambda: client.tool("logic_edit", "select_all"), delay=0.4)
        step("logic_edit.quantize 1/16", "edit", lambda: client.tool("logic_edit", "quantize", {"value": "1/16"}), delay=0.6)
        step("logic_navigate.zoom_to_fit", "navigate", lambda: client.tool("logic_navigate", "zoom_to_fit"), delay=0.7)

        for uri in ["logic://tracks", "logic://tracks/0/regions", "logic://tracks/1/regions", "logic://tracks/2/regions", "logic://tracks/3/regions", "logic://mixer"]:
            step(f"readback {uri}", "readback", lambda uri=uri: client.resource(uri), delay=0.2)

        step("logic_project.get_regions", "project", lambda: client.tool("logic_project", "get_regions"), delay=0.4)
        step("logic_plugins.get_inventory track 0", "plugins", lambda: client.tool("logic_plugins", "get_inventory", {"track": 0}), delay=0.4)
        step("safety: insert_plugin without confirmation", "safety", lambda: client.tool("logic_mixer", "insert_plugin", {"track": 0, "slot": 0, "plugin_name": "Gain"}), delay=0.4)

        return_to_start()
        step("logic_transport.play final", "transport", lambda: client.tool("logic_transport", "play"), delay=6.0)
        step("logic_transport.stop final", "transport", lambda: client.tool("logic_transport", "stop"), delay=0.5)
        click_stop()
        step("logic://workflow-skills/search?query=bounce", "workflow", lambda: client.resource("logic://workflow-skills/search?query=bounce"), delay=0.5)
    finally:
        client.close()
        stop_capture(capture)

    states = {state: sum(1 for event in events if event["state"] == state) for state in sorted({event["state"] for event in events})}
    families = sorted(set(event["family"] for event in events))
    transcript = {
        "generated_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "raw_video": str(RAW_VIDEO),
        "logic_language": "English via com.apple.logic10 AppleLanguages=[en]",
        "demo_note": "Fresh project with varied visible track types: Software Instrument, Drummer/Session Player, Audio, External MIDI.",
        "event_count": len(events),
        "states": states,
        "families": families,
        "events": events,
    }
    TRANSCRIPT.write_text(json.dumps(transcript, ensure_ascii=False, indent=2))
    print(f"captured {RAW_VIDEO}")
    print(f"transcript {TRANSCRIPT}")
    print(f"states {states}")


if __name__ == "__main__":
    main()
