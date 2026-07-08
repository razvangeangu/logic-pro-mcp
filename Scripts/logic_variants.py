"""Logic Pro variant names/bundle IDs (manifest.json) and shared AppleScript helpers."""

from __future__ import annotations

import json
import os
import subprocess
from collections.abc import Callable
from dataclasses import dataclass
from functools import lru_cache
from pathlib import Path
from typing import Sequence

REPO_ROOT = Path(__file__).resolve().parent.parent
MANIFEST_PATH = REPO_ROOT / "manifest.json"
BUNDLE_ID_ENV = "LOGIC_PRO_BUNDLE_ID"

LOGIC_APP_NAME = "Logic Pro"


def _normalize_variants(raw_variants: list[dict[str, str]]) -> tuple[dict[str, str], ...]:
    return tuple(
        {
            "name": v["name"],
            "bundle_id": v["bundle_id"],
            "process_name": v["process_name"],
            "default_install_path": v["default_install_path"],
        }
        for v in raw_variants
    )


@lru_cache(maxsize=1)
def manifest_variants() -> tuple[dict[str, str], ...]:
    if MANIFEST_PATH.is_file():
        manifest = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))
        return _normalize_variants(manifest["supported_logic_pro_variants"])
    return (
        {
            "name": "desktop",
            "bundle_id": "com.apple.logic10",
            "process_name": "Logic Pro",
            "default_install_path": "/Applications/Logic Pro.app",
        },
        {
            "name": "creator_studio",
            "bundle_id": "com.apple.mobilelogic",
            "process_name": "Logic Pro Creator Studio",
            "default_install_path": "/Applications/Logic Pro Creator Studio.app",
        },
    )


@lru_cache(maxsize=1)
def manifest_bundle_ids_in_order() -> tuple[str, ...]:
    return tuple(v["bundle_id"] for v in manifest_variants())


@lru_cache(maxsize=1)
def process_name_by_bundle_id() -> dict[str, str]:
    return {v["bundle_id"]: v["process_name"] for v in manifest_variants()}


@lru_cache(maxsize=1)
def logic_app_names() -> frozenset[str]:
    return frozenset(v["process_name"] for v in manifest_variants())


@lru_cache(maxsize=1)
def known_bundle_ids() -> frozenset[str]:
    return frozenset(manifest_bundle_ids_in_order())


def bundle_ids_in_priority_order() -> tuple[str, ...]:
    """Resolution order: forced env override, else manifest order (desktop before Creator Studio)."""
    forced = os.environ.get(BUNDLE_ID_ENV, "").strip()
    if forced:
        return (forced,)
    return manifest_bundle_ids_in_order()


def process_names_in_priority_order() -> tuple[str, ...]:
    names_by_bundle = process_name_by_bundle_id()
    names: list[str] = []
    for bundle_id in bundle_ids_in_priority_order():
        process_name = names_by_bundle.get(bundle_id)
        if process_name and process_name not in names:
            names.append(process_name)
    for process_name in names_by_bundle.values():
        if process_name not in names:
            names.append(process_name)
    return tuple(names)


def process_name_for_bundle_id(bundle_id: str) -> str:
    return process_name_by_bundle_id().get(bundle_id, bundle_id)


def is_logic_frontmost_app(name: str | None) -> bool:
    return bool(name and name in logic_app_names())


def jxa_find_process_snippet(*, se_binding: str = "se", proc_var: str = "proc") -> str:
    """JavaScript that assigns the first running Logic process to ``proc_var``."""
    names_json = json.dumps(list(process_names_in_priority_order()))
    return f"""const processNames = {names_json};
let {proc_var} = null;
for (const processName of processNames) {{
  try {{
    const candidate = {se_binding}.processes.byName(processName);
    if (candidate !== null) {{
      {proc_var} = candidate;
      break;
    }}
  }} catch (error) {{}}
}}"""


def blocking_dialog_subrole_jxa() -> str:
    find_process = jxa_find_process_snippet(se_binding="se", proc_var="proc")
    return "\n".join(
        [
            "function safe(fn, fallback) { try { return fn(); } catch (e) { return fallback; } }",
            'function str(v) { return v === undefined || v === null ? "" : String(v); }',
            'const se = Application("System Events");',
            find_process,
            "if (proc === null) { JSON.stringify({status: \"no_process\"}); }",
            "else {",
            "  const wins = safe(() => proc.windows(), []);",
            "  let blocking = false;",
            "  for (let i = 0; i < wins.length; i += 1) {",
            '    const sr = str(safe(() => wins[i].subrole(), ""));',
            '    if (sr === "AXDialog" || sr === "AXSystemDialog") { blocking = true; break; }',
            "  }",
            '  JSON.stringify({status: "ok", blocking: blocking});',
            "}",
        ]
    )


@dataclass(frozen=True)
class AppleScriptProbe:
    output: str | None
    error: str | None


def _escape_applescript_string(value: str) -> str:
    return value.replace("\\", "\\\\").replace('"', '\\"')


def system_events_process_lines(process_name: str, body_lines: Sequence[str]) -> list[str]:
    escaped = _escape_applescript_string(process_name)
    return [
        'tell application "System Events"',
        f'tell application process "{escaped}"',
        *body_lines,
        "end tell",
        "end tell",
    ]


def run_osascript_probe(lines: Sequence[str], timeout_sec: float = 3.0) -> AppleScriptProbe:
    args = ["/usr/bin/osascript"]
    for line in lines:
        args.extend(["-e", line])
    try:
        result = subprocess.run(
            args,
            capture_output=True,
            text=True,
            timeout=timeout_sec,
            check=False,
        )
    except FileNotFoundError:
        return AppleScriptProbe(None, "osascript_not_found")
    except subprocess.TimeoutExpired:
        return AppleScriptProbe(None, "osascript_timeout")
    if result.returncode != 0:
        detail = (result.stderr or result.stdout or "").strip()
        if len(detail) > 240:
            detail = detail[:237] + "..."
        suffix = f": {detail}" if detail else ""
        return AppleScriptProbe(None, f"osascript_exit_{result.returncode}{suffix}")
    return AppleScriptProbe(result.stdout.strip(), None)


def run_osascript(lines: Sequence[str], timeout_sec: float = 3.0) -> str | None:
    return run_osascript_probe(lines, timeout_sec=timeout_sec).output


def logic_process_osa(body: str, timeout_sec: float = 8.0) -> str:
    body_lines = [line for line in body.splitlines()]
    for logic_pro_process_name in process_names_in_priority_order():
        output = run_osascript(
            system_events_process_lines(logic_pro_process_name, body_lines),
            timeout_sec=timeout_sec,
        )
        if output is not None and output.strip():
            return output.strip()
    return ""


def logic_process_osa_with_runner(body: str, run_osa: Callable[[str, float], str], timeout_sec: float = 8.0) -> str:
    body_lines = [line for line in body.splitlines()]
    for logic_pro_process_name in process_names_in_priority_order():
        script = "\n".join(system_events_process_lines(logic_pro_process_name, body_lines))
        result = run_osa(script, timeout_sec).strip()
        if result:
            return result
    return ""


def split_lines(output: str | None) -> list[str]:
    if not output:
        return []
    return [line.strip() for line in output.splitlines() if line.strip()]


def activate_logic() -> bool:
    for logic_pro_bundle_id in bundle_ids_in_priority_order():
        if run_osascript(
            [f'tell application id "{logic_pro_bundle_id}" to activate'],
            timeout_sec=2.0,
        ) is not None:
            return True
    try:
        for logic_pro_bundle_id in bundle_ids_in_priority_order():
            result = subprocess.run(
                ["/usr/bin/open", "-b", logic_pro_bundle_id],
                capture_output=True,
                text=True,
                timeout=2.0,
                check=False,
            )
            if result.returncode == 0:
                return True
        for logic_pro_process_name in process_names_in_priority_order():
            result = subprocess.run(
                ["/usr/bin/open", "-a", logic_pro_process_name],
                capture_output=True,
                text=True,
                timeout=2.0,
                check=False,
            )
            if result.returncode == 0:
                return True
    except (FileNotFoundError, subprocess.TimeoutExpired):
        return False
    return False


def logic_document_open_probe(timeout_sec: float = 2.0) -> tuple[bool | None, str | None]:
    for logic_pro_bundle_id in bundle_ids_in_priority_order():
        result = run_osascript_probe(
            [
                f'tell application id "{logic_pro_bundle_id}"',
                "return count of documents as text",
                "end tell",
            ],
            timeout_sec=timeout_sec,
        )
        if result.error:
            continue
        raw = (result.output or "").strip()
        try:
            return int(raw) > 0, None
        except ValueError:
            return None, f"document_count_invalid:{raw!r}"
    return None, "document_probe_failed"


def logic_window_names_probe() -> tuple[list[str], str | None]:
    last_error: str | None = None
    for logic_pro_process_name in process_names_in_priority_order():
        result = run_osascript_probe(
            system_events_process_lines(
                logic_pro_process_name,
                [
                    "set AppleScript's text item delimiters to linefeed",
                    "return (name of windows) as text",
                ],
            ),
            timeout_sec=2.0,
        )
        names = split_lines(result.output)
        if names:
            return names, result.error
        last_error = result.error
    return [], last_error


def logic_menu_items_probe() -> tuple[list[str], str | None]:
    last_error: str | None = None
    for logic_pro_process_name in process_names_in_priority_order():
        result = run_osascript_probe(
            system_events_process_lines(
                logic_pro_process_name,
                [
                    "set AppleScript's text item delimiters to linefeed",
                    "return (name of menu bar items of menu bar 1) as text",
                ],
            ),
            timeout_sec=2.0,
        )
        items = split_lines(result.output)
        if items:
            return items, result.error
        last_error = result.error
    return [], last_error
