#!/usr/bin/env python3
# SIZE_OK: T0 spike centralizes live MCP orchestration and the required inline SMF extractor.
# /// script
# requires-python = ">=3.9"
# dependencies = []
# ///

# --- How to run ---
# 1. Build the server binary first, or set LOGIC_PRO_MCP_BINARY.
# 2. Run: python3 Scripts/spike-midi-export.py
# 3. The script prints newline-delimited JSON progress records.
# ------------------

from __future__ import annotations

from dataclasses import dataclass
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import threading
import time
from typing import Any, Dict, List, Optional, Tuple


BINARY = os.environ.get("LOGIC_PRO_MCP_BINARY", ".build/release/LogicProMCP")
TIMEOUT = float(os.environ.get("LOGIC_PRO_MCP_SPIKE_TIMEOUT", "20"))
SENTINEL_BAR = 3
SENTINEL_NOTES = "60,0,500,100,1;64,500,500,100,1;67,1000,500,100,1"
EXPECTED_RELATIVE = [(60, 0.0, 1.0, 1), (64, 1.0, 1.0, 1), (67, 2.0, 1.0, 1)]
EXPORT_DIR = Path(os.environ.get("LOGIC_PRO_MCP_MIDI_EXPORT_DIR", "/tmp/LogicProMCP-spike"))
EXPORT_FILENAME = os.environ.get("LOGIC_PRO_MCP_MIDI_EXPORT_FILENAME", "selection.mid")
EXPORT_POLL_SECONDS = 5.0
RESOURCE_READY_URI = "logic://tracks"
RESOURCE_READY_TIMEOUT_SECONDS = 12.0
RESOURCE_READY_INTERVAL_SECONDS = 1.0


EXPORT_MENU_SCRIPT = r'''
set outputLines to {}
set titleSeparator to " ||| "
on cleanText(value)
    try
        if value is missing value then return ""
        return value as text
    on error
        return ""
    end try
end cleanText
on recordLine(kind, firstIndex, secondIndex, firstTitle, secondTitle)
    return kind & tab & (firstIndex as text) & tab & (secondIndex as text) & tab & firstTitle & tab & secondTitle
end recordLine
on joinList(textList, separatorText)
    set cleanedList to {}
    repeat with textItem in textList
        copy my cleanText(textItem) to end of cleanedList
    end repeat
    set previousDelimiters to AppleScript's text item delimiters
    set AppleScript's text item delimiters to separatorText
    set joinedText to cleanedList as text
    set AppleScript's text item delimiters to previousDelimiters
    return joinedText
end joinList
on appendSubmenuLines(parentIndex, parentTitle, childTitleList)
    global outputLines, titleSeparator
    copy "SUBMENU_TITLES" & tab & (parentIndex as text) & tab & parentTitle & tab & titleSeparator & tab & my joinList(childTitleList, titleSeparator) to end of outputLines
    repeat with childIndex from 1 to count of childTitleList
        set childTitle to my cleanText(item childIndex of childTitleList)
        copy my recordLine("SUBMENU", parentIndex, childIndex, parentTitle, childTitle) to end of outputLines
    end repeat
end appendSubmenuLines
tell application "Logic Pro" to activate
delay 0.2
tell application "System Events" to tell process "Logic Pro" to click menu bar item 3 of menu bar 1
delay 0.2
tell application "System Events"
    tell process "Logic Pro"
        set frontmost to true
        set fileMenuItem to menu bar item 3 of menu bar 1
        set fileMenu to menu 1 of fileMenuItem
        set titleList to name of every menu item of menu 1 of menu bar item 3 of menu bar 1
        copy "FILE_TITLES" & tab & titleSeparator & tab & my joinList(titleList, titleSeparator) to end of outputLines
        set foundMIDI to false
        set foundExportParent to false
        set clickedFileIndex to 0
        set clickedSubmenuIndex to 0
        set clickedTitle to ""
        set enumeratedParentTitles to my joinList(titleList, titleSeparator)
        repeat with fileIndex from 1 to count of titleList
            set fileItem to menu item fileIndex of fileMenu
            set fileTitle to my cleanText(item fileIndex of titleList)
            copy my recordLine("FILE", fileIndex, 0, fileTitle, "") to end of outputLines
            set skipParent to false
            ignoring case
                if fileTitle is "Open Recent" then set skipParent to true
            end ignoring
            if fileTitle is "최근" then set skipParent to true
            if skipParent then
                copy my recordLine("SKIPPED_PARENT", fileIndex, 0, fileTitle, "explicit skip") to end of outputLines
            else
                set isExportParent to false
                ignoring case
                    if fileTitle is "Export" then set isExportParent to true
                end ignoring
                if fileTitle is "보내기" then set isExportParent to true
                if isExportParent then
                    set foundExportParent to true
                    if exists menu 1 of fileItem then
                        set childTitleList to name of every menu item of menu 1 of fileItem
                        my appendSubmenuLines(fileIndex, fileTitle, childTitleList)
                        repeat with subIndex from 1 to count of childTitleList
                            set subTitle to my cleanText(item subIndex of childTitleList)
                            if subTitle contains "Selection as MIDI" then
                                set clickedFileIndex to fileIndex
                                set clickedSubmenuIndex to subIndex
                                set clickedTitle to subTitle
                                click fileItem
                                delay 0.2
                                click menu item subIndex of menu 1 of fileItem
                                set foundMIDI to true
                                exit repeat
                            end if
                        end repeat
                    end if
                end if
            end if
            if foundMIDI then exit repeat
        end repeat
        if foundMIDI is false then
            key code 53
            if foundExportParent is false then
                copy "FAILED" & tab & "No File > Export parent found" & tab & enumeratedParentTitles to end of outputLines
            else
                copy "FAILED" & tab & "File > Export found but no child containing MIDI" & tab & enumeratedParentTitles to end of outputLines
            end if
        else
            copy my recordLine("CLICKED", clickedFileIndex, clickedSubmenuIndex, clickedTitle, "") to end of outputLines
        end if
    end tell
end tell
set AppleScript's text item delimiters to linefeed
return outputLines as text
'''


SAVE_DIALOG_SCRIPT = r'''
set targetDir to __TARGET_DIR__
set fileName to __FILE_NAME__
set filenameStatus to "default-name"
set overwriteStatus to "not-needed"
on cleanText(value)
    try
        if value is missing value then return ""
        return value as text
    on error
        return ""
    end try
end cleanText
tell application "Logic Pro" to activate
delay 0.2
tell application "System Events"
    tell process "Logic Pro"
        set frontmost to true
        set dialogFound to false
        repeat with attempt from 1 to 20
            try
                if exists sheet 1 of window 1 then
                    set dialogFound to true
                    exit repeat
                end if
                if exists window 1 then
                    set windowSubrole to my cleanText(subrole of window 1)
                    if windowSubrole contains "Dialog" then
                        set dialogFound to true
                        exit repeat
                    end if
                end if
            end try
            delay 0.25
        end repeat
        if dialogFound is false then error "Save dialog did not appear"
        keystroke "g" using {command down, shift down}
        delay 0.3
        keystroke targetDir
        key code 36
        delay 0.8
        try
            if exists sheet 1 of window 1 then
                set targetSheet to sheet 1 of window 1
                if exists text field 1 of targetSheet then
                    set value of text field 1 of targetSheet to fileName
                    set filenameStatus to "sheet text field 1"
                end if
            else if exists text field 1 of window 1 then
                set value of text field 1 of window 1 to fileName
                set filenameStatus to "window text field 1"
            end if
        on error errMsg number errNum
            set filenameStatus to "default-name: " & errMsg
        end try
        key code 36
        delay 0.8
        try
            if exists sheet 1 of window 1 then
                key code 36
                delay 0.3
                set overwriteStatus to "return-sent"
            end if
        on error errMsg number errNum
            set overwriteStatus to "return-failed: " & errMsg
        end try
    end tell
end tell
return "SAVE" & tab & filenameStatus & tab & overwriteStatus
'''


DELETE_TRACK_KEYSTROKE_SCRIPT = r'''
tell application "Logic Pro" to activate
delay 0.1
tell application "System Events"
    tell process "Logic Pro"
        set frontmost to true
        key code 51 using {command down}
        delay 0.5
        set confirmationStatus to "not-found"
        try
            if exists sheet 1 of window 1 then
                key code 36
                set confirmationStatus to "sheet-return-sent"
            else if exists window 1 then
                set windowSubrole to ""
                try
                    set windowSubrole to subrole of window 1 as text
                end try
                if windowSubrole contains "Dialog" then
                    key code 36
                    set confirmationStatus to "window-return-sent"
                end if
            end if
        on error errMsg number errNum
            set confirmationStatus to "confirmation-error: " & errMsg
        end try
    end tell
end tell
return "DELETE_KEYSTROKE" & tab & confirmationStatus
'''


DIALOG_TREE_SCRIPT = r'''
set outputLines to {}
on cleanText(value)
    try
        if value is missing value then return ""
        return value as text
    on error
        return ""
    end try
end cleanText
on describeElement(kind, item)
    set itemRole to ""
    set itemTitle to ""
    try
        set itemRole to my cleanText(role of item)
    end try
    try
        set itemTitle to my cleanText(name of item)
    end try
    return kind & tab & itemRole & tab & itemTitle
end describeElement
tell application "Logic Pro" to activate
delay 0.1
tell application "System Events"
    tell process "Logic Pro"
        set frontmost to true
        if exists window 1 then
            set frontWindow to window 1
            copy my describeElement("WINDOW", frontWindow) to end of outputLines
            repeat with childElement in UI elements of frontWindow
                copy my describeElement("WINDOW_CHILD", childElement) to end of outputLines
            end repeat
            repeat with targetSheet in sheets of frontWindow
                copy my describeElement("SHEET", targetSheet) to end of outputLines
                repeat with childElement in UI elements of targetSheet
                    copy my describeElement("CHILD", childElement) to end of outputLines
                    try
                        repeat with grandchildElement in UI elements of childElement
                            copy my describeElement("GRANDCHILD", grandchildElement) to end of outputLines
                        end repeat
                    end try
                end repeat
            end repeat
        else
            copy "NO_WINDOW" & tab & "" & tab & "" to end of outputLines
        end if
    end tell
end tell
set AppleScript's text item delimiters to linefeed
return outputLines as text
'''


ESCAPE_SCRIPT = 'tell application "System Events" to key code 53'
ESCAPE_TWICE_SCRIPT = r'''
tell application "System Events"
    key code 53
    delay 0.3
    key code 53
end tell
'''


@dataclass(frozen=True)
class MidiNote:
    pitch: int
    velocity: int
    start_beats: float
    duration_beats: float
    channel: int


@dataclass(frozen=True)
class OsascriptResult:
    returncode: int
    stdout_lines: List[str]
    stderr: str
    timed_out: bool


class MCPClient:
    def __init__(self) -> None:
        stderr_dir = tempfile.TemporaryDirectory(prefix="logic-mcp-spike.")
        self._stderr_dir = stderr_dir
        self._stderr_file = open(Path(stderr_dir.name) / "stderr.txt", "w")
        self.proc = subprocess.Popen(
            [BINARY],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=self._stderr_file,
            bufsize=0,
            env=os.environ.copy(),
        )
        self.responses: Dict[int, Dict[str, Any]] = {}
        self._reader = threading.Thread(target=self._read_loop, daemon=True)
        self._reader.start()

    def _read_loop(self) -> None:
        if self.proc.stdout is None:
            return
        for raw_line in self.proc.stdout:
            line = raw_line.decode("utf-8", errors="replace").strip()
            if not line:
                continue
            try:
                message = json.loads(line)
            except json.JSONDecodeError:
                continue
            message_id = message.get("id")
            if isinstance(message_id, int) and ("result" in message or "error" in message):
                self.responses[message_id] = message

    def send(self, message: Dict[str, Any], timeout: Optional[float] = None) -> Optional[Dict[str, Any]]:
        if self.proc.stdin is None:
            return None
        try:
            self.proc.stdin.write((json.dumps(message) + "\n").encode("utf-8"))
            self.proc.stdin.flush()
        except BrokenPipeError:
            return None
        message_id = message.get("id")
        if not isinstance(message_id, int):
            return None
        deadline = time.time() + (timeout if timeout is not None else TIMEOUT)
        while time.time() < deadline:
            if message_id in self.responses:
                return self.responses.pop(message_id)
            time.sleep(0.02)
        return None

    def notify(self, message: Dict[str, Any]) -> None:
        if self.proc.stdin is None:
            return
        try:
            self.proc.stdin.write((json.dumps(message) + "\n").encode("utf-8"))
            self.proc.stdin.flush()
        except BrokenPipeError:
            return

    def close(self) -> None:
        if self.proc.stdin is not None:
            try:
                self.proc.stdin.close()
            except OSError:
                pass
        try:
            self.proc.terminate()
            self.proc.wait(timeout=3)
        except subprocess.TimeoutExpired:
            self.proc.kill()
        self._stderr_file.close()
        self._stderr_dir.cleanup()


_NEXT_ID = 1


def next_id() -> int:
    global _NEXT_ID
    request_id = _NEXT_ID
    _NEXT_ID += 1
    return request_id


def emit(step: str, status: str, **fields: Any) -> None:
    failed_statuses = {"blocked", "empty_or_unavailable", "failed", "mismatch", "missing", "timeout"}
    payload = {
        "step": step,
        "step_id": step,
        "ok": status not in failed_statuses,
        "status": status,
        "evidence": fields,
    }
    print(json.dumps(payload, sort_keys=True), flush=True)


def applescript_literal(value: str) -> str:
    return '"' + value.replace("\\", "\\\\").replace('"', '\\"') + '"'


def run_osascript(step: str, script: str, timeout: float) -> OsascriptResult:
    try:
        result = subprocess.run(
            ["osascript", "-e", script],
            capture_output=True,
            check=False,
            text=True,
            timeout=timeout,
        )
    except subprocess.TimeoutExpired as error:
        stdout = error.stdout.decode("utf-8", errors="replace") if isinstance(error.stdout, bytes) else (error.stdout or "")
        stderr = error.stderr.decode("utf-8", errors="replace") if isinstance(error.stderr, bytes) else (error.stderr or "")
        stdout_lines = [line for line in stdout.splitlines() if line]
        emit(f"osascript_{step}", "timeout", timeout=timeout, stdout=stdout_lines, stderr=stderr)
        return OsascriptResult(returncode=124, stdout_lines=stdout_lines, stderr=stderr, timed_out=True)
    stdout_lines = [line for line in result.stdout.splitlines() if line]
    emit(
        f"osascript_{step}",
        "ok" if result.returncode == 0 else "failed",
        returncode=result.returncode,
        stdout=stdout_lines,
        stderr=result.stderr,
    )
    return OsascriptResult(
        returncode=result.returncode,
        stdout_lines=stdout_lines,
        stderr=result.stderr,
        timed_out=False,
    )


def initialize(client: MCPClient) -> bool:
    response = client.send({
        "jsonrpc": "2.0",
        "id": 0,
        "method": "initialize",
        "params": {
            "protocolVersion": "2024-11-05",
            "capabilities": {},
            "clientInfo": {"name": "midi-export-spike", "version": "1"},
        },
    })
    ok = isinstance(response, dict) and "result" in response
    emit("initialize", "ok" if ok else "failed", response=response)
    if ok:
        client.notify({"jsonrpc": "2.0", "method": "notifications/initialized"})
        time.sleep(1.0)
    return ok


def call_tool(
    client: MCPClient,
    tool: str,
    command: str,
    params: Optional[Dict[str, Any]] = None,
    timeout: Optional[float] = None,
) -> Optional[Dict[str, Any]]:
    arguments: Dict[str, Any] = {"command": command}
    if params is not None:
        arguments["params"] = params
    return client.send({
        "jsonrpc": "2.0",
        "id": next_id(),
        "method": "tools/call",
        "params": {"name": tool, "arguments": arguments},
    }, timeout=timeout)


def read_resource(client: MCPClient, uri: str, timeout: Optional[float] = None) -> Optional[Dict[str, Any]]:
    return client.send({
        "jsonrpc": "2.0",
        "id": next_id(),
        "method": "resources/read",
        "params": {"uri": uri},
    }, timeout=timeout)


def list_tools(client: MCPClient) -> List[Dict[str, Any]]:
    response = client.send({"jsonrpc": "2.0", "id": next_id(), "method": "tools/list", "params": {}})
    tools = (((response or {}).get("result") or {}).get("tools") or [])
    return tools if isinstance(tools, list) else []


def response_text(response: Optional[Dict[str, Any]], key: str) -> str:
    try:
        entries = response["result"][key]
    except (KeyError, TypeError):
        return ""
    for entry in entries:
        if isinstance(entry, dict) and entry.get("type") == "text":
            return str(entry.get("text", ""))
    return ""


def parsed_json_text(text: str) -> Any:
    try:
        return json.loads(text)
    except json.JSONDecodeError:
        return None


def tool_json(response: Optional[Dict[str, Any]]) -> Any:
    return parsed_json_text(response_text(response, "content"))


def resource_envelope(response: Optional[Dict[str, Any]]) -> Optional[Dict[str, Any]]:
    if not isinstance(response, dict) or "error" in response:
        return None
    result = response.get("result")
    if not isinstance(result, dict):
        return None
    contents = result.get("contents")
    if not isinstance(contents, list) or not contents:
        return None
    first = contents[0]
    if not isinstance(first, dict):
        return None
    text = first.get("text")
    if not isinstance(text, str):
        return None
    parsed = parsed_json_text(text)
    if not isinstance(parsed, dict):
        return None
    data = parsed.get("data")
    if isinstance(data, (list, dict)):
        return parsed
    return None


def resource_json(response: Optional[Dict[str, Any]]) -> Any:
    envelope = resource_envelope(response)
    return envelope["data"] if envelope is not None else None


def wait_for_resource_ready(client: MCPClient, uri: str = RESOURCE_READY_URI) -> bool:
    deadline = time.time() + RESOURCE_READY_TIMEOUT_SECONDS
    last_response: Optional[Dict[str, Any]] = None
    while time.time() < deadline:
        last_response = read_resource(client, uri, timeout=RESOURCE_READY_INTERVAL_SECONDS)
        if resource_envelope(last_response) is not None:
            emit("resource_ready", "ok", uri=uri)
            return True
        remaining = deadline - time.time()
        if remaining > 0:
            time.sleep(min(RESOURCE_READY_INTERVAL_SECONDS, remaining))
    emit("resource_ready", "timeout", uri=uri, timeout_seconds=RESOURCE_READY_TIMEOUT_SECONDS, response=last_response)
    return False


def tracks_snapshot(client: MCPClient) -> Optional[List[Dict[str, Any]]]:
    tracks = resource_json(read_resource(client, "logic://tracks"))
    return tracks if isinstance(tracks, list) else None


def read_vlq(data: bytes, offset: int) -> Tuple[int, int]:
    value = 0
    for _ in range(4):
        if offset >= len(data):
            raise ValueError("truncated VLQ")
        byte = data[offset]
        offset += 1
        value = (value << 7) | (byte & 0x7F)
        if byte & 0x80 == 0:
            return value, offset
    raise ValueError("oversized VLQ")


def read_u16(data: bytes, offset: int) -> int:
    return (data[offset] << 8) | data[offset + 1]


def read_u32(data: bytes, offset: int) -> int:
    return (data[offset] << 24) | (data[offset + 1] << 16) | (data[offset + 2] << 8) | data[offset + 3]


def extract_smf_notes(path: Path) -> List[MidiNote]:
    data = path.read_bytes()
    if data[:4] != b"MThd":
        raise ValueError("missing MThd")
    header_len = read_u32(data, 4)
    fmt = read_u16(data, 8)
    track_count = read_u16(data, 10)
    division = read_u16(data, 12)
    if fmt not in (0, 1) or division & 0x8000:
        raise ValueError("unsupported SMF header")
    pos = 8 + header_len
    notes: List[MidiNote] = []
    for _ in range(track_count):
        if data[pos:pos + 4] != b"MTrk":
            raise ValueError("missing MTrk")
        length = read_u32(data, pos + 4)
        pos += 8
        end = pos + length
        parse_track(data[pos:end], division, notes)
        pos = end
    return sorted(notes, key=lambda n: (n.start_beats, n.pitch, n.channel))


def parse_track(data: bytes, division: int, notes: List[MidiNote]) -> None:
    pos = 0
    tick = 0
    running: Optional[int] = None
    active: Dict[Tuple[int, int], List[Tuple[int, int]]] = {}
    while pos < len(data):
        delta, pos = read_vlq(data, pos)
        tick += delta
        first = data[pos]
        pos += 1
        if first == 0xFF:
            pos += 1
            length, pos = read_vlq(data, pos)
            pos += length
            running = None
            continue
        if first in (0xF0, 0xF7):
            length, pos = read_vlq(data, pos)
            pos += length
            running = None
            continue
        data_bytes: List[int] = []
        if first < 0x80:
            if running is None:
                raise ValueError("running status without status")
            status = running
            data_bytes.append(first)
        else:
            status = first
            running = status
        high = status & 0xF0
        data_count = 1 if high in (0xC0, 0xD0) else 2
        while len(data_bytes) < data_count:
            data_bytes.append(data[pos])
            pos += 1
        if high not in (0x80, 0x90):
            continue
        pitch = data_bytes[0]
        velocity = data_bytes[1]
        channel = (status & 0x0F) + 1
        key = (pitch, channel)
        if high == 0x90 and velocity > 0:
            active.setdefault(key, []).append((tick, velocity))
        else:
            started = active.get(key, [])
            if not started:
                raise ValueError("unmatched note off")
            start_tick, start_velocity = started.pop(0)
            notes.append(MidiNote(
                pitch=pitch,
                velocity=start_velocity,
                start_beats=tick_to_beats(start_tick, division),
                duration_beats=tick_to_beats(tick - start_tick, division),
                channel=channel,
            ))
    if any(active.values()):
        raise ValueError("dangling notes")


def tick_to_beats(ticks: int, division: int) -> float:
    return ticks / float(division)


def sentinel_matches(notes: List[MidiNote]) -> bool:
    if len(notes) < len(EXPECTED_RELATIVE):
        return False
    first_start = notes[0].start_beats
    observed = [
        (note.pitch, round(note.start_beats - first_start, 3), round(note.duration_beats, 3), note.channel)
        for note in notes[:len(EXPECTED_RELATIVE)]
    ]
    return observed == EXPECTED_RELATIVE


def enumerate_regions(client: MCPClient, track_index: Optional[int]) -> List[Dict[str, Any]]:
    project_regions = tool_json(call_tool(client, "logic_project", "get_regions"))
    if isinstance(project_regions, list):
        emit("enumerate_regions", "ok", source="logic_project.get_regions", count=len(project_regions))
        return project_regions
    if track_index is not None:
        track_regions = resource_json(read_resource(client, f"logic://tracks/{track_index}/regions"))
        if isinstance(track_regions, list):
            emit("enumerate_regions", "ok", source="track_regions_resource", count=len(track_regions))
            return track_regions
    emit("enumerate_regions", "failed", project_response=project_regions)
    return []


def emit_osascript_records(step: str, lines: List[str]) -> None:
    for line in lines:
        parts = line.split("\t")
        if not parts:
            continue
        kind = parts[0]
        if kind == "FILE_TITLES" and len(parts) >= 3:
            emit(step, "ok", kind=kind, separator=parts[1], titles=parts[2])
        elif kind == "SUBMENU_TITLES" and len(parts) >= 5:
            emit(step, "ok", kind=kind, file_index=parts[1], parent_title=parts[2], separator=parts[3], titles=parts[4])
        elif kind == "FILE" and len(parts) >= 5:
            emit(step, "ok", kind=kind, file_index=parts[1], title=parts[3])
        elif kind == "SKIPPED_PARENT" and len(parts) >= 5:
            emit(step, "ok", kind=kind, file_index=parts[1], title=parts[3], reason=parts[4])
        elif kind == "SUBMENU" and len(parts) >= 5:
            emit(
                step,
                "ok",
                kind=kind,
                file_index=parts[1],
                submenu_index=parts[2],
                parent_title=parts[3],
                title=parts[4],
            )
        elif kind == "CLICKED" and len(parts) >= 5:
            emit(step, "ok", kind=kind, file_index=parts[1], submenu_index=parts[2], title=parts[3])
        elif kind == "FAILED" and len(parts) >= 2:
            parent_titles = parts[2] if len(parts) >= 3 else None
            emit(step, "failed", kind=kind, reason=parts[1], parent_titles=parent_titles)
        elif kind == "SAVE" and len(parts) >= 3:
            emit(step, "ok", kind=kind, filename_status=parts[1], overwrite_status=parts[2])
        elif kind == "DELETE_KEYSTROKE" and len(parts) >= 2:
            emit(step, "ok", kind=kind, confirmation_status=parts[1])
        elif kind in {"WINDOW", "WINDOW_CHILD", "SHEET", "CHILD", "GRANDCHILD", "NO_WINDOW"} and len(parts) >= 3:
            emit(step, "ok", kind=kind, role=parts[1], title=parts[2])
        else:
            emit(step, "ok", raw=line)


def send_escape(label: str = "escape_fallback") -> None:
    run_osascript(label, ESCAPE_SCRIPT, timeout=3)


def send_escape_twice(label: str = "escape_twice_fallback") -> None:
    run_osascript(label, ESCAPE_TWICE_SCRIPT, timeout=4)


def report_dialog_ax_tree(label: str) -> None:
    result = run_osascript(f"{label}_ax_tree", DIALOG_TREE_SCRIPT, timeout=5)
    emit_osascript_records("dialog_ax_tree", result.stdout_lines)


def fail_ui_step(step: str, **evidence: Any) -> None:
    report_dialog_ax_tree(step)
    send_escape(f"{step}_escape_fallback")
    emit(step, "failed", **evidence)


def click_export_selection_as_midi() -> bool:
    result = run_osascript("export_menu_click", EXPORT_MENU_SCRIPT, timeout=8)
    emit_osascript_records("export_menu_enumeration", result.stdout_lines)
    clicked = any(line.startswith("CLICKED\t") for line in result.stdout_lines)
    if result.returncode != 0 or not clicked:
        fail_ui_step("export_menu_click", returncode=result.returncode, clicked=clicked, stderr=result.stderr)
        return False
    return True


def handle_save_dialog(export_dir: Path, filename: str) -> bool:
    script = (
        SAVE_DIALOG_SCRIPT
        .replace("__TARGET_DIR__", applescript_literal(str(export_dir)))
        .replace("__FILE_NAME__", applescript_literal(filename))
    )
    result = run_osascript("save_dialog", script, timeout=10)
    emit_osascript_records("save_dialog", result.stdout_lines)
    if result.returncode != 0:
        fail_ui_step("save_dialog", returncode=result.returncode, stderr=result.stderr)
        return False
    return True


def midi_file_snapshot(export_dir: Path) -> Dict[str, int]:
    snapshot: Dict[str, int] = {}
    for path in export_dir.glob("*.mid"):
        try:
            snapshot[str(path)] = path.stat().st_mtime_ns
        except OSError:
            continue
    return snapshot


def poll_exported_midi(export_dir: Path, before: Dict[str, int]) -> Optional[Path]:
    deadline = time.time() + EXPORT_POLL_SECONDS
    latest: Optional[Path] = None
    while time.time() < deadline:
        changed: List[Path] = []
        for path in export_dir.glob("*.mid"):
            try:
                stat = path.stat()
            except OSError:
                continue
            if stat.st_size > 0 and stat.st_mtime_ns > before.get(str(path), 0):
                changed.append(path)
        if changed:
            latest = max(changed, key=lambda candidate: candidate.stat().st_mtime_ns)
            break
        time.sleep(0.1)
    emit("poll_exported_midi", "ok" if latest else "failed", path=str(latest) if latest else None, timeout_seconds=EXPORT_POLL_SECONDS)
    return latest


def cleanup_created_tracks(client: MCPClient, original_count: int, created_indices: List[int]) -> None:
    send_escape_twice("cleanup_pre_escape")
    try:
        for index in sorted(set(created_indices), reverse=True):
            params = {"index": index}
            response = call_tool(client, "logic_tracks", "select", params, timeout=30)
            emit("cleanup_track_select", "requested", index=index, params=params, response=tool_json(response) or response_text(response, "content"))
            delete_result = run_osascript("cleanup_track_delete", DELETE_TRACK_KEYSTROKE_SCRIPT, timeout=6)
            emit_osascript_records("cleanup_track_delete", delete_result.stdout_lines)
            if delete_result.returncode != 0:
                emit("cleanup_track_delete", "failed", index=index, returncode=delete_result.returncode, stderr=delete_result.stderr)
        final_tracks = tracks_snapshot(client)
        if final_tracks is None:
            emit(
                "cleanup_final_track_count",
                "failed",
                baseline_count=original_count,
                created_track_indices=created_indices,
                reason="tracks resource read failed or returned malformed envelope",
            )
            return
        final_count = len(final_tracks)
        emit(
            "cleanup_final_track_count",
            "ok" if final_count == original_count else "failed",
            baseline_count=original_count,
            final_count=final_count,
            created_track_indices=created_indices,
        )
    finally:
        send_escape("cleanup_post_escape")


def run_probe(client: MCPClient, tools: List[Dict[str, Any]], export_dir: Path) -> Tuple[bool, Optional[int], List[int]]:
    before_tracks = tracks_snapshot(client)
    if before_tracks is None:
        emit("snapshot_tracks", "failed", reason="tracks resource read failed or returned malformed envelope")
        return False, None, []
    before_count = len(before_tracks)
    emit("snapshot_tracks", "ok", count=before_count)

    record_response = call_tool(
        client,
        "logic_tracks",
        "record_sequence",
        {"bar": SENTINEL_BAR, "notes": SENTINEL_NOTES, "tempo": 120},
        timeout=60,
    )
    record_payload = tool_json(record_response)
    emit("record_sequence_sentinel", "sent", response=record_payload or response_text(record_response, "content"))

    after_tracks = tracks_snapshot(client)
    after_count = len(after_tracks) if after_tracks is not None else None
    created_indices: List[int] = []
    created_track = None
    if isinstance(record_payload, dict) and isinstance(record_payload.get("created_track"), int):
        created_track = record_payload["created_track"]
    if after_tracks is not None and len(after_tracks) >= before_count + 1:
        created_indices = list(range(before_count, len(after_tracks)))
    elif created_track is not None:
        created_indices = [created_track]
    if created_track is None and created_indices:
        created_track = before_count
    emit(
        "created_track_identity",
        "ok" if created_track is not None else "missing",
        index=created_track,
        baseline_count=before_count,
        after_count=after_count,
        cleanup_indices=created_indices,
    )

    regions = enumerate_regions(client, created_track)
    region_identity = regions[-1] if regions else None
    emit(
        "region_selection_hypothesis",
        "ok",
        marker="HYPOTHESIS_RECORD_SEQUENCE_IMPORTED_REGION_REMAINS_SELECTED",
        action="skip_explicit_region_selection",
        proof="exported MIDI sentinel comparison",
        created_track=created_track,
        region_identity=region_identity,
        server_tools_seen=[tool.get("name") for tool in tools],
    )

    before_files = midi_file_snapshot(export_dir)
    if not click_export_selection_as_midi():
        return False, before_count, created_indices
    if not handle_save_dialog(export_dir, EXPORT_FILENAME):
        return False, before_count, created_indices
    exported = poll_exported_midi(export_dir, before_files)
    if exported is None:
        fail_ui_step("verify_export_file", expected_dir=str(export_dir), reason="no new or modified MIDI export file found")
        return False, before_count, created_indices

    notes = extract_smf_notes(exported)
    matched = sentinel_matches(notes)
    emit("verify_export_file", "ok" if matched else "mismatch", path=str(exported), parsed_notes=[note.__dict__ for note in notes])
    if not matched:
        send_escape("verify_export_file_escape_fallback")
    return matched, before_count, created_indices


def main() -> int:
    export_dir = EXPORT_DIR
    export_dir.mkdir(parents=True, exist_ok=True)
    emit("controlled_export_dir", "ok", path=str(export_dir))

    client = MCPClient()
    before_count: Optional[int] = None
    created_track_indices: List[int] = []
    try:
        if not initialize(client):
            return 2
        if not wait_for_resource_ready(client):
            return 2
        tools = list_tools(client)
        ok, probe_before_count, probe_created_indices = run_probe(client, tools, export_dir)
        if probe_before_count is not None:
            before_count = probe_before_count
            created_track_indices = probe_created_indices
        return 0 if ok else 2
    finally:
        if before_count is not None:
            cleanup_created_tracks(client, before_count, created_track_indices)
        client.close()


if __name__ == "__main__":
    sys.exit(main())
