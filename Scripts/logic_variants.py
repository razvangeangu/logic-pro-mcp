"""Logic Pro variant names/bundle IDs (manifest.json) and shared AppleScript helpers."""

from __future__ import annotations

import json
import os
import subprocess
from collections.abc import Callable, Sequence
from dataclasses import dataclass
from functools import lru_cache
from pathlib import Path

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
def install_path_by_bundle_id() -> dict[str, str]:
    return {v["bundle_id"]: v["default_install_path"] for v in manifest_variants()}


@lru_cache(maxsize=1)
def logic_app_names() -> frozenset[str]:
    return frozenset(v["process_name"] for v in manifest_variants())


@lru_cache(maxsize=1)
def known_bundle_ids() -> frozenset[str]:
    return frozenset(manifest_bundle_ids_in_order())


def bundle_ids_in_priority_order() -> tuple[str, ...]:
    """Forced env override alone, else full manifest order (activate/launch fallbacks)."""
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


def resolve_bundle_id(
    *,
    forced_bundle_id: str | None,
    frontmost_bundle_id: str | None,
    is_running: Callable[[str], bool],
    is_installed: Callable[[str], bool],
) -> str:
    """Match Swift LogicProVariantPolicy.resolveBundleID selection order."""
    forced = (forced_bundle_id or "").strip()
    if forced:
        return forced
    known = list(manifest_bundle_ids_in_order())
    known_set = set(known)
    if frontmost_bundle_id and frontmost_bundle_id in known_set:
        return frontmost_bundle_id
    for bundle_id in known:
        if is_running(bundle_id):
            return bundle_id
    for bundle_id in known:
        if is_installed(bundle_id):
            return bundle_id
    return known[0]


@dataclass(frozen=True)
class ResolvedLogicTarget:
    bundle_id: str
    process_name: str


def resolve_logic_target(
    *,
    forced_bundle_id: str | None = None,
    frontmost_bundle_id: str | None = None,
    is_running: Callable[[str], bool] | None = None,
    is_installed: Callable[[str], bool] | None = None,
) -> ResolvedLogicTarget:
    """Resolve one concrete Logic target (bundle + process name)."""
    if forced_bundle_id is None:
        forced_bundle_id = os.environ.get(BUNDLE_ID_ENV)
    if is_running is None:
        is_running = production_is_running
    if is_installed is None:
        is_installed = production_is_installed
    if frontmost_bundle_id is None and not (forced_bundle_id or "").strip():
        frontmost_bundle_id = production_frontmost_bundle_id()
    bundle_id = resolve_bundle_id(
        forced_bundle_id=forced_bundle_id,
        frontmost_bundle_id=frontmost_bundle_id,
        is_running=is_running,
        is_installed=is_installed,
    )
    return ResolvedLogicTarget(
        bundle_id=bundle_id,
        process_name=process_name_for_bundle_id(bundle_id),
    )


def production_frontmost_bundle_id() -> str | None:
    output = run_osascript(
        [
            'tell application "System Events"',
            "try",
            "return bundle identifier of first application process whose frontmost is true",
            "on error",
            'return ""',
            "end try",
            "end tell",
        ],
        timeout_sec=2.0,
    )
    value = (output or "").strip()
    return value or None


def production_is_running(bundle_id: str) -> bool:
    process_name = process_name_for_bundle_id(bundle_id)
    escaped = _escape_applescript_string(process_name)
    output = run_osascript(
        [
            'tell application "System Events"',
            f'if exists application process "{escaped}" then',
            'return "1"',
            "else",
            'return "0"',
            "end if",
            "end tell",
        ],
        timeout_sec=2.0,
    )
    return (output or "").strip() == "1"


def production_is_installed(bundle_id: str) -> bool:
    path = install_path_by_bundle_id().get(bundle_id)
    if path and Path(path).exists():
        return True
    return False


def select_jxa_process_name(process_names: Sequence[str], exists: Callable[[str], bool]) -> str | None:
    """Pure selector mirroring jxa_find_process_snippet existence gating."""
    for process_name in process_names:
        if exists(process_name):
            return process_name
    return None


def jxa_find_process_snippet(*, se_binding: str = "se", proc_var: str = "proc") -> str:
    """JavaScript that assigns the first *existing* Logic process to ``proc_var``."""
    names_json = json.dumps(list(process_names_in_priority_order()))
    return f"""const processNames = {names_json};
let {proc_var} = null;
for (const processName of processNames) {{
  try {{
    const candidate = {se_binding}.processes.byName(processName);
    if (candidate && candidate.exists()) {{
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


def resolve_logic_target_from_env_or_default() -> ResolvedLogicTarget:
    """Resolve without live System Events probes (forced env, else first known).

    Used by injectable ``*_with_runner`` helpers so tests can supply a fake
    ``run_osa`` without hanging on Accessibility. Production live paths use
    ``resolve_logic_target`` (frontmost → running → installed).
    """
    forced = os.environ.get(BUNDLE_ID_ENV, "").strip()
    if forced:
        return ResolvedLogicTarget(bundle_id=forced, process_name=process_name_for_bundle_id(forced))
    bundle_id = manifest_bundle_ids_in_order()[0]
    return ResolvedLogicTarget(bundle_id=bundle_id, process_name=process_name_for_bundle_id(bundle_id))


def logic_process_osa(
    body: str,
    timeout_sec: float = 8.0,
    *,
    resolve_target: Callable[[], ResolvedLogicTarget] | None = None,
) -> str:
    """Query helper: resolve one target, return non-empty stdout or \"\"."""
    target = (resolve_target or resolve_logic_target)()
    body_lines = [line for line in body.splitlines()]
    output = run_osascript(
        system_events_process_lines(target.process_name, body_lines),
        timeout_sec=timeout_sec,
    )
    if output is not None and output.strip():
        return output.strip()
    return ""


def logic_process_osa_action(
    body: str,
    timeout_sec: float = 8.0,
    *,
    resolve_target: Callable[[], ResolvedLogicTarget] | None = None,
) -> bool:
    """Action helper: resolve one target; exit 0 succeeds even with empty stdout."""
    target = (resolve_target or resolve_logic_target)()
    body_lines = [line for line in body.splitlines()]
    output = run_osascript(
        system_events_process_lines(target.process_name, body_lines),
        timeout_sec=timeout_sec,
    )
    return output is not None


def logic_process_osa_with_runner(
    body: str,
    run_osa: Callable[[str, float], str],
    timeout_sec: float = 8.0,
    *,
    resolve_target: Callable[[], ResolvedLogicTarget] | None = None,
) -> str:
    """Query-style runner helper: resolve once; return stripped stdout (may be empty)."""
    target = (resolve_target or resolve_logic_target_from_env_or_default)()
    body_lines = [line for line in body.splitlines()]
    script = "\n".join(system_events_process_lines(target.process_name, body_lines))
    return run_osa(script, timeout_sec).strip()


def logic_process_osa_action_with_runner(
    body: str,
    run_osa: Callable[[str, float], str],
    timeout_sec: float = 8.0,
    *,
    resolve_target: Callable[[], ResolvedLogicTarget] | None = None,
) -> str:
    """Action-style runner helper: resolve once; empty stdout is still a completed send."""
    return logic_process_osa_with_runner(
        body,
        run_osa,
        timeout_sec=timeout_sec,
        resolve_target=resolve_target,
    )


def split_lines(output: str | None) -> list[str]:
    if not output:
        return []
    return [line.strip() for line in output.splitlines() if line.strip()]


def activate_logic() -> bool:
    target = resolve_logic_target()
    if run_osascript(
        [f'tell application id "{target.bundle_id}" to activate'],
        timeout_sec=2.0,
    ) is not None:
        return True
    try:
        result = subprocess.run(
            ["/usr/bin/open", "-b", target.bundle_id],
            capture_output=True,
            text=True,
            timeout=2.0,
            check=False,
        )
        if result.returncode == 0:
            return True
        result = subprocess.run(
            ["/usr/bin/open", "-a", target.process_name],
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
    target = resolve_logic_target()
    result = run_osascript_probe(
        [
            f'tell application id "{target.bundle_id}"',
            "return count of documents as text",
            "end tell",
        ],
        timeout_sec=timeout_sec,
    )
    if result.error:
        return None, result.error
    raw = (result.output or "").strip()
    try:
        return int(raw) > 0, None
    except ValueError:
        return None, f"document_count_invalid:{raw!r}"


def logic_window_names_probe() -> tuple[list[str], str | None]:
    target = resolve_logic_target()
    result = run_osascript_probe(
        system_events_process_lines(
            target.process_name,
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
    return [], result.error


def logic_menu_items_probe() -> tuple[list[str], str | None]:
    target = resolve_logic_target()
    result = run_osascript_probe(
        system_events_process_lines(
            target.process_name,
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
    return [], result.error
