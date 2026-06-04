#!/usr/bin/env python3
"""Sequentially import v4 MIDI parts through LogicProMCP.

This prevents stacked Logic import dialogs. It sends one JSON-RPC request at a
time and requires the import response to contain verified:true before moving on.
Run only after Logic Pro has a project open.
"""

from __future__ import annotations

import argparse
import json
import select
import shutil
import subprocess
import sys
import time
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parent
REPO_ROOT = ROOT.parents[1]
REQUESTS = ROOT / "v4-import-requests.jsonl"
DEFAULT_RESPONSE_TIMEOUT_SEC = 45.0


def json_lines(path: Path) -> list[dict[str, Any]]:
    return [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]


def prepare_tmp_midis(requests: list[dict[str, Any]]) -> list[Path]:
    copied: list[Path] = []
    for request in requests:
        params = request["params"]["arguments"]["params"]
        target = Path(params["path"])
        source = ROOT / "midi" / target.name
        if not source.exists():
            raise FileNotFoundError(source)
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, target)
        copied.append(target)
    return copied


def cleanup_tmp_midis(paths: list[Path]) -> None:
    for path in paths:
        if path.name.startswith("v4_") and path.suffix == ".mid":
            path.unlink(missing_ok=True)


def read_response(proc: subprocess.Popen[str], request_id: int, timeout_sec: float) -> dict[str, Any]:
    if proc.stdout is None:
        raise RuntimeError("LogicProMCP stdout pipe is not available")

    deadline = time.monotonic() + timeout_sec
    while time.monotonic() < deadline:
        remaining = max(0.0, deadline - time.monotonic())
        ready, _, _ = select.select([proc.stdout], [], [], remaining)
        if not ready:
            continue
        line = proc.stdout.readline() if proc.stdout else ""
        if line == "":
            raise RuntimeError(f"LogicProMCP exited before response id {request_id}")
        try:
            obj = json.loads(line)
        except json.JSONDecodeError:
            continue
        if obj.get("id") == request_id:
            return obj
    raise TimeoutError(f"Timed out after {timeout_sec:.1f}s waiting for response id {request_id}")


def send(proc: subprocess.Popen[str], request: dict[str, Any], timeout_sec: float) -> dict[str, Any]:
    assert proc.stdin is not None
    proc.stdin.write(json.dumps(request, separators=(",", ":")) + "\n")
    proc.stdin.flush()
    return read_response(proc, int(request["id"]), timeout_sec)


def tool_text(response: dict[str, Any]) -> dict[str, Any]:
    result = response.get("result") or {}
    content = result.get("content") or []
    if not content:
        return {}
    text = content[0].get("text", "")
    try:
        return json.loads(text)
    except json.JSONDecodeError:
        return {"raw": text}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--mcp", default=str(REPO_ROOT / ".build/release/LogicProMCP"))
    parser.add_argument("--timeout-sec", type=float, default=DEFAULT_RESPONSE_TIMEOUT_SEC)
    args = parser.parse_args()

    requests = json_lines(REQUESTS)
    copied: list[Path] = []
    proc = subprocess.Popen(
        [args.mcp],
        cwd=REPO_ROOT,
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        bufsize=1,
    )
    try:
        copied = prepare_tmp_midis(requests)
        init = {
            "jsonrpc": "2.0",
            "id": 1,
            "method": "initialize",
            "params": {
                "protocolVersion": "2024-11-05",
                "capabilities": {},
                "clientInfo": {"name": "v4-import-sequential", "version": "1.0"},
            },
        }
        send(proc, init, args.timeout_sec)
        tempo = {
            "jsonrpc": "2.0",
            "id": 2,
            "method": "tools/call",
            "params": {
                "name": "logic_transport",
                "arguments": {"command": "set_tempo", "params": {"bpm": 127}},
            },
        }
        tempo_payload = tool_text(send(proc, tempo, args.timeout_sec))
        if tempo_payload.get("verified") is not True:
            print(f"tempo not verified: {tempo_payload}", file=sys.stderr)
            return 2

        for offset, request in enumerate(requests, start=20):
            request["id"] = offset
            response = send(proc, request, args.timeout_sec)
            payload = tool_text(response)
            if payload.get("verified") is not True:
                print(f"import failed for id {offset}: {payload}", file=sys.stderr)
                return 3
            print(f"imported {payload.get('requested')} delta={payload.get('observed_delta')}")
    except TimeoutError as error:
        print(str(error), file=sys.stderr)
        return 4
    finally:
        cleanup_tmp_midis(copied)
        proc.terminate()
        try:
            proc.wait(timeout=2)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait(timeout=2)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
