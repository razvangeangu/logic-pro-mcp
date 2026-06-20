#!/usr/bin/env python3
"""Reusable fresh-session bootstrap helper for Logic Pro live/demo runs.

This helper uses MCP-visible truth for project/document state and System Events
only for UI readiness signals such as frontmost app, window titles, and menu
language. It never relies on coordinate clicks.
"""

from __future__ import annotations

import json
import os
import subprocess
import time
from dataclasses import asdict, dataclass, field
from typing import Any, Callable, Mapping, Sequence

LOGIC_APP_NAME = "Logic Pro"
PROJECT_PICKER_MARKERS = (
    "choose a project",
    "choose project",
    "new from template",
    "프로젝트 선택",
)
NEW_TRACK_DIALOG_MARKERS = (
    "new tracks",
    "create tracks",
    "create new track",
    "새로운 트랙 생성",
    "트랙 생성",
)
LANGUAGE_MENU_MARKERS = {
    "en": frozenset({"File", "Edit", "Track"}),
    "ko": frozenset({"파일", "편집", "트랙"}),
}


def _safe_json(text: str) -> Any:
    try:
        return json.loads(text)
    except Exception:
        return None


def _bool_env(env: Mapping[str, str], name: str, default: bool) -> bool:
    raw = env.get(name)
    if raw is None:
        return default
    return raw.strip().lower() not in {"0", "false", "no", "off", ""}


def _int_env(env: Mapping[str, str], name: str, default: int) -> int:
    raw = env.get(name)
    if raw is None:
        return default
    try:
        return int(raw)
    except ValueError:
        return default


def _float_env(env: Mapping[str, str], name: str, default: float) -> float:
    raw = env.get(name)
    if raw is None:
        return default
    try:
        return float(raw)
    except ValueError:
        return default


def _string_list_env(env: Mapping[str, str], name: str) -> tuple[str, ...]:
    raw = env.get(name, "")
    values = [item.strip() for item in raw.split(",")]
    return tuple(item for item in values if item)


@dataclass(frozen=True)
class BootstrapConfig:
    expected_language: str | None
    hide_apps: tuple[str, ...]
    max_tracks: int
    allow_launch: bool
    allow_new_project: bool
    confirm_new_track_dialog: bool
    timeout_sec: float
    poll_interval_sec: float

    @classmethod
    def from_env(cls, strict_live: bool, env: Mapping[str, str] | None = None) -> "BootstrapConfig":
        env = env or os.environ
        expected_language = env.get("LOGIC_PRO_MCP_BOOTSTRAP_LANGUAGE", "en").strip().lower()
        if expected_language in {"", "any", "auto"}:
            expected_language = None
        return cls(
            expected_language=expected_language,
            hide_apps=_string_list_env(env, "LOGIC_PRO_MCP_BOOTSTRAP_HIDE_APPS"),
            max_tracks=max(0, _int_env(env, "LOGIC_PRO_MCP_BOOTSTRAP_MAX_TRACKS", 1)),
            allow_launch=_bool_env(env, "LOGIC_PRO_MCP_BOOTSTRAP_ALLOW_LAUNCH", True),
            allow_new_project=_bool_env(env, "LOGIC_PRO_MCP_BOOTSTRAP_ALLOW_NEW_PROJECT", strict_live),
            confirm_new_track_dialog=_bool_env(
                env, "LOGIC_PRO_MCP_BOOTSTRAP_CONFIRM_NEW_TRACK_DIALOG", True
            ),
            timeout_sec=max(1.0, _float_env(env, "LOGIC_PRO_MCP_BOOTSTRAP_TIMEOUT_SEC", 8.0)),
            poll_interval_sec=max(0.1, _float_env(env, "LOGIC_PRO_MCP_BOOTSTRAP_POLL_SEC", 0.35)),
        )


@dataclass(frozen=True)
class UISnapshot:
    frontmost_app: str | None
    logic_window_names: list[str]
    logic_menu_items: list[str]
    detected_language: str | None
    project_picker_visible: bool
    new_track_dialog_visible: bool


@dataclass(frozen=True)
class FreshSessionAssessment:
    ok: bool
    reason: str | None = None
    hint: str | None = None
    inferred_track_count: int = 0
    placeholder_count: int = 0
    region_count: int = 0


@dataclass
class BootstrapResult:
    ok: bool
    reason: str | None = None
    hint: str | None = None
    actions: list[str] = field(default_factory=list)
    ui: dict[str, Any] = field(default_factory=dict)
    health: dict[str, Any] = field(default_factory=dict)
    project: dict[str, Any] = field(default_factory=dict)
    tracks: dict[str, Any] = field(default_factory=dict)
    regions: dict[str, Any] = field(default_factory=dict)

    def as_dict(self) -> dict[str, Any]:
        return {
            "ok": self.ok,
            "reason": self.reason,
            "hint": self.hint,
            "actions": list(self.actions),
            "ui": self.ui,
            "health": self.health,
            "project": self.project,
            "tracks": self.tracks,
            "regions": self.regions,
        }


def detect_language(menu_items: Sequence[str]) -> str | None:
    menu_set = {item.strip() for item in menu_items if item and item.strip()}
    for language, required_items in LANGUAGE_MENU_MARKERS.items():
        if required_items.issubset(menu_set):
            return language
    return None


def _contains_marker(window_names: Sequence[str], markers: Sequence[str]) -> bool:
    haystack = [name.lower() for name in window_names]
    for marker in markers:
        marker_lc = marker.lower()
        if any(marker_lc in name for name in haystack):
            return True
    return False


def _project_info_data(project_payload: Any) -> dict[str, Any]:
    if isinstance(project_payload, dict):
        data = project_payload.get("data")
        if isinstance(data, dict):
            return data
    return {}


def _track_rows(tracks_payload: Any) -> list[dict[str, Any]]:
    if isinstance(tracks_payload, dict):
        data = tracks_payload.get("data")
        if isinstance(data, list):
            return [row for row in data if isinstance(row, dict)]
    return []


def _health_cache_summary(health: dict[str, Any]) -> dict[str, Any]:
    cache = health.get("cache", {}) if isinstance(health, dict) else {}
    return cache if isinstance(cache, dict) else {}


def _fallback_project_payload(health: dict[str, Any]) -> dict[str, Any] | None:
    cache = _health_cache_summary(health)
    project_name = cache.get("project")
    track_count = cache.get("track_count")
    if not isinstance(project_name, str) and not isinstance(track_count, int):
        return None
    return {
        "source": "health_cache",
        "data": {
            "name": project_name if isinstance(project_name, str) else "",
            "trackCount": track_count if isinstance(track_count, int) else 0,
            "source": "health_cache",
        },
    }


def evaluate_fresh_session(
    ui: UISnapshot,
    health: dict[str, Any],
    project_payload: Any,
    tracks_payload: Any,
    region_count: int,
    config: BootstrapConfig,
) -> FreshSessionAssessment:
    permissions = health.get("permissions", {}) if isinstance(health, dict) else {}

    if health.get("logic_pro_running") is not True:
        return FreshSessionAssessment(False, "logic_not_running", "Launch Logic Pro before continuing.")
    if permissions.get("accessibility") is not True:
        return FreshSessionAssessment(
            False,
            "missing_accessibility",
            "Grant Accessibility access to this session before running live automation.",
        )
    if health.get("logic_pro_has_window") is not True:
        return FreshSessionAssessment(
            False,
            "logic_window_not_visible",
            "Bring a Logic Pro document window on-screen before continuing.",
        )
    if ui.frontmost_app != LOGIC_APP_NAME:
        return FreshSessionAssessment(
            False,
            "logic_not_frontmost",
            "Logic Pro must be the frontmost app so modal/readback state is trustworthy.",
        )
    if config.expected_language:
        if ui.detected_language is None:
            return FreshSessionAssessment(
                False,
                "language_unrecognized",
                "Could not infer the Logic Pro UI language from the menu bar.",
            )
        if ui.detected_language != config.expected_language:
            return FreshSessionAssessment(
                False,
                "language_mismatch",
                f"Expected a {config.expected_language} Logic UI but detected {ui.detected_language}.",
            )
    if ui.project_picker_visible:
        return FreshSessionAssessment(
            False,
            "project_picker_visible",
            "The Choose Project picker is still visible; do not continue into a polluted session.",
        )
    if ui.new_track_dialog_visible:
        return FreshSessionAssessment(
            False,
            "new_track_dialog_visible",
            "Logic's new-track dialog is still open; the empty project is not ready yet.",
        )
    if health.get("logic_pro_has_document") is not True:
        return FreshSessionAssessment(
            False,
            "no_document_open",
            "No Logic project document is currently open.",
        )

    project_data = _project_info_data(project_payload)
    project_source = None
    if isinstance(project_payload, dict):
        project_source = project_payload.get("source")
    if not project_source:
        project_source = project_data.get("source")
    if not project_data or project_source == "default":
        return FreshSessionAssessment(
            False,
            "project_info_unavailable",
            "Project metadata never advanced beyond the default envelope.",
        )

    track_rows = _track_rows(tracks_payload)
    placeholder_count = sum(1 for row in track_rows if row.get("placeholder") is True)
    if isinstance(tracks_payload, dict) and tracks_payload.get("ax_occluded") is True:
        return FreshSessionAssessment(
            False,
            "ax_occluded",
            "The Logic AX tree is occluded by a modal or floating window.",
        )
    if placeholder_count > 0:
        return FreshSessionAssessment(
            False,
            "tracks_not_live",
            "Track readback is still in placeholder mode instead of a live arrange-window read.",
            placeholder_count=placeholder_count,
        )

    project_track_count = project_data.get("trackCount")
    if not isinstance(project_track_count, int):
        project_track_count = 0
    inferred_track_count = max(project_track_count, len(track_rows))
    if inferred_track_count > config.max_tracks:
        return FreshSessionAssessment(
            False,
            "polluted_session",
            f"Expected at most {config.max_tracks} fresh track(s), observed {inferred_track_count}.",
            inferred_track_count=inferred_track_count,
            placeholder_count=placeholder_count,
        )
    if region_count > 0:
        return FreshSessionAssessment(
            False,
            "existing_regions_present",
            f"Expected an empty project, but observed {region_count} region(s) on track 0.",
            inferred_track_count=inferred_track_count,
            placeholder_count=placeholder_count,
            region_count=region_count,
        )

    return FreshSessionAssessment(
        True,
        inferred_track_count=inferred_track_count,
        placeholder_count=placeholder_count,
        region_count=region_count,
    )


def _run_osascript(lines: Sequence[str], timeout_sec: float = 3.0) -> str | None:
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
    except (FileNotFoundError, subprocess.TimeoutExpired):
        return None
    if result.returncode != 0:
        return None
    return result.stdout.strip()


def _split_lines(output: str | None) -> list[str]:
    if not output:
        return []
    return [line.strip() for line in output.splitlines() if line.strip()]


def _activate_logic() -> bool:
    return (
        _run_osascript([f'tell application "{LOGIC_APP_NAME}" to activate'], timeout_sec=2.0)
        is not None
    )


def _hide_application(name: str) -> bool:
    escaped = name.replace("\\", "\\\\").replace('"', '\\"')
    output = _run_osascript(
        [
            f'tell application "{escaped}"',
            "if it is running then hide",
            "end tell",
        ],
        timeout_sec=2.0,
    )
    return output is not None


def _send_return_key() -> bool:
    output = _run_osascript(
        ['tell application "System Events" to key code 36'],
        timeout_sec=2.0,
    )
    return output is not None


def _frontmost_application() -> str | None:
    return _run_osascript(
        ['tell application "System Events" to get name of first application process whose frontmost is true'],
        timeout_sec=2.0,
    )


def _logic_window_names() -> list[str]:
    output = _run_osascript(
        [
            'tell application "System Events"',
            f'if not (exists application process "{LOGIC_APP_NAME}") then return ""',
            f'tell application process "{LOGIC_APP_NAME}"',
            "set AppleScript's text item delimiters to linefeed",
            "return (name of windows) as text",
            "end tell",
            "end tell",
        ],
        timeout_sec=2.0,
    )
    return _split_lines(output)


def _logic_menu_items() -> list[str]:
    output = _run_osascript(
        [
            'tell application "System Events"',
            f'tell application process "{LOGIC_APP_NAME}"',
            "set AppleScript's text item delimiters to linefeed",
            "return (name of menu bar items of menu bar 1) as text",
            "end tell",
            "end tell",
        ],
        timeout_sec=2.0,
    )
    return _split_lines(output)


def collect_ui_snapshot() -> UISnapshot:
    window_names = _logic_window_names()
    menu_items = _logic_menu_items()
    return UISnapshot(
        frontmost_app=_frontmost_application(),
        logic_window_names=window_names,
        logic_menu_items=menu_items,
        detected_language=detect_language(menu_items),
        project_picker_visible=_contains_marker(window_names, PROJECT_PICKER_MARKERS),
        new_track_dialog_visible=_contains_marker(window_names, NEW_TRACK_DIALOG_MARKERS),
    )


def _response_is_error(response: Any) -> bool:
    try:
        return bool(response["result"].get("isError", False))
    except Exception:
        return True


def _tool_json(
    call_tool: Callable[[str, str, dict[str, Any] | None, float | None], Any],
    tool_text: Callable[[Any], str],
    tool: str,
    command: str,
    params: dict[str, Any] | None = None,
    timeout: float | None = None,
) -> tuple[Any, str, Any]:
    response = call_tool(tool, command, params or None, timeout)
    text = tool_text(response)
    return response, text, _safe_json(text)


def _resource_json(
    read_resource: Callable[[str], Any],
    resource_text: Callable[[Any], str],
    uri: str,
) -> tuple[Any, str, Any]:
    response = read_resource(uri)
    text = resource_text(response)
    return response, text, _safe_json(text)


def bootstrap_fresh_logic_session(
    *,
    call_tool: Callable[[str, str, dict[str, Any] | None, float | None], Any],
    read_resource: Callable[[str], Any],
    tool_text: Callable[[Any], str],
    resource_text: Callable[[Any], str],
    strict_live: bool,
    log: Callable[[str], None] = print,
    env: Mapping[str, str] | None = None,
) -> BootstrapResult:
    config = BootstrapConfig.from_env(strict_live=strict_live, env=env)
    actions: list[str] = []

    def blocked(
        reason: str,
        hint: str,
        *,
        health: dict[str, Any] | None = None,
        project: dict[str, Any] | None = None,
        tracks: dict[str, Any] | None = None,
        regions: dict[str, Any] | None = None,
        ui: UISnapshot | None = None,
    ) -> BootstrapResult:
        return BootstrapResult(
            ok=False,
            reason=reason,
            hint=hint,
            actions=actions,
            ui=asdict(ui) if ui else {},
            health=health or {},
            project=project or {},
            tracks=tracks or {},
            regions=regions or {},
        )

    def fetch_health() -> tuple[Any, dict[str, Any] | None]:
        response, text, parsed = _tool_json(call_tool, tool_text, "logic_system", "health", timeout=5.0)
        if _response_is_error(response) or not isinstance(parsed, dict):
            log(f"  [bootstrap] system.health unavailable: {text or response!r}")
            return response, None
        return response, parsed

    def wait_for(predicate: Callable[[], bool], timeout_sec: float) -> bool:
        deadline = time.time() + timeout_sec
        while time.time() < deadline:
            if predicate():
                return True
            time.sleep(config.poll_interval_sec)
        return False

    _, health = fetch_health()
    if health is None:
        return blocked("health_unavailable", "Could not read logic_system.health from the MCP server.")

    if health.get("logic_pro_running") is not True:
        if not config.allow_launch:
            return blocked(
                "logic_not_running",
                "Logic Pro is not running and auto-launch is disabled.",
                health=health,
            )
        log("  [bootstrap] launching Logic Pro")
        response = call_tool("logic_project", "launch", None, 10.0)
        actions.append("logic_project.launch")
        if _response_is_error(response):
            return blocked(
                "logic_launch_failed",
                tool_text(response) or "logic_project.launch failed",
                health=health,
            )
        if not wait_for(lambda: (fetch_health()[1] or {}).get("logic_pro_running") is True, config.timeout_sec):
            _, latest = fetch_health()
            return blocked(
                "logic_launch_timeout",
                "Logic Pro did not reach a running state after launch.",
                health=latest or health,
            )
        _, health = fetch_health()
        if health is None:
            return blocked("health_unavailable", "Could not read health after launching Logic Pro.")

    for app_name in config.hide_apps:
        if _hide_application(app_name):
            actions.append(f"hide:{app_name}")

    _activate_logic()
    actions.append("activate:Logic Pro")

    ui = collect_ui_snapshot()
    if ui.frontmost_app != LOGIC_APP_NAME:
        wait_for(lambda: (_activate_logic() or True) and collect_ui_snapshot().frontmost_app == LOGIC_APP_NAME, 2.0)
        ui = collect_ui_snapshot()

    if health.get("logic_pro_has_document") is not True:
        if not config.allow_new_project:
            return blocked(
                "no_document_open",
                "No Logic document is open and auto-new-project is disabled.",
                health=health,
                ui=ui,
            )
        log("  [bootstrap] creating a fresh Logic document")
        response = call_tool("logic_project", "new", None, 10.0)
        actions.append("logic_project.new")
        if _response_is_error(response):
            return blocked(
                "new_project_failed",
                tool_text(response) or "logic_project.new failed",
                health=health,
                ui=ui,
            )
        call_tool("logic_system", "refresh_cache", None, 5.0)
        actions.append("logic_system.refresh_cache")

        deadline = time.time() + config.timeout_sec
        sent_return = False
        while time.time() < deadline:
            time.sleep(config.poll_interval_sec)
            _activate_logic()
            _, health = fetch_health()
            if health is None:
                continue
            ui = collect_ui_snapshot()
            if (
                ui.new_track_dialog_visible
                and config.confirm_new_track_dialog
                and not sent_return
            ):
                permissions = health.get("permissions", {})
                if permissions.get("post_event_access") is not True:
                    return blocked(
                        "post_event_access_denied",
                        "Need CGEvent post-event access to confirm Logic's new-track dialog.",
                        health=health,
                        ui=ui,
                    )
                if _send_return_key():
                    actions.append("confirm_new_track_dialog:return")
                    sent_return = True
                    call_tool("logic_system", "refresh_cache", None, 5.0)
                    actions.append("logic_system.refresh_cache")
                    continue

            if (
                health.get("logic_pro_has_document") is True
                and health.get("logic_pro_has_window") is True
                and not ui.project_picker_visible
                and not ui.new_track_dialog_visible
            ):
                break
        else:
            return blocked(
                "fresh_project_not_ready",
                "Logic did not settle into a usable fresh project before timeout.",
                health=health or {},
                ui=ui,
            )

    call_tool("logic_system", "refresh_cache", None, 5.0)
    if "logic_system.refresh_cache" not in actions:
        actions.append("logic_system.refresh_cache")
    time.sleep(config.poll_interval_sec)

    _, health = fetch_health()
    if health is None:
        return blocked("health_unavailable", "Could not read health after bootstrap actions.", ui=ui)
    ui = collect_ui_snapshot()

    _, _, project_payload = _resource_json(read_resource, resource_text, "logic://project/info")
    _, _, tracks_payload = _resource_json(read_resource, resource_text, "logic://tracks")
    if not isinstance(project_payload, dict):
        project_payload = _fallback_project_payload(health)
        if project_payload is not None:
            actions.append("fallback:system.health.cache.project")
        else:
            return blocked(
                "project_info_unavailable",
                "logic://project/info did not return JSON and no cache fallback was available.",
                health=health,
                ui=ui,
            )
    if not isinstance(tracks_payload, dict):
        cached_track_count = _health_cache_summary(health).get("track_count")
        if isinstance(cached_track_count, int) and cached_track_count > config.max_tracks:
            return blocked(
                "polluted_session",
                f"Expected at most {config.max_tracks} fresh track(s), observed {cached_track_count} in the cached session state.",
                health=health,
                project=project_payload,
                tracks={
                    "source": "health_cache",
                    "count": cached_track_count,
                },
                ui=ui,
            )
        return blocked(
            "tracks_unavailable",
            "logic://tracks did not return JSON.",
            health=health,
            project=project_payload,
            ui=ui,
        )

    region_count = 0
    if _track_rows(tracks_payload):
        _, _, regions_payload = _resource_json(read_resource, resource_text, "logic://tracks/0/regions")
        if isinstance(regions_payload, list):
            region_count = len(regions_payload)

    assessment = evaluate_fresh_session(
        ui=ui,
        health=health,
        project_payload=project_payload,
        tracks_payload=tracks_payload,
        region_count=region_count,
        config=config,
    )

    result = BootstrapResult(
        ok=assessment.ok,
        reason=assessment.reason,
        hint=assessment.hint,
        actions=actions,
        ui=asdict(ui),
        health=health,
        project={
            "source": project_payload.get("source"),
            "data": _project_info_data(project_payload),
        },
        tracks={
            "source": tracks_payload.get("source"),
            "ax_occluded": tracks_payload.get("ax_occluded"),
            "count": len(_track_rows(tracks_payload)),
            "placeholder_count": assessment.placeholder_count,
        },
        regions={"track0_count": region_count},
    )
    return result
