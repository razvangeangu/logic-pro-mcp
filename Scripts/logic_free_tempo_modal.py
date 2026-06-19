#!/usr/bin/env python3
"""Detect and deterministically resolve Logic Pro's Free Tempo Recording modal."""

from __future__ import annotations

import json
import subprocess
import sys
import time
from copy import deepcopy
from typing import Any

PROCESS_NAME = "Logic Pro"
LIST_SEPARATOR = "||"
STATE_SEPARATOR = "::"
MODAL_MARKERS = (
    "Free Tempo Recording",
    "analyze region tempo",
    "project tempo",
    "Don't show again",
)

DEFAULT_FREE_TEMPO_POLICY: dict[str, Any] = {
    "policy_id": "keep_project_tempo_no_analysis",
    "selection_labels": ["Don't analyze region tempo or change project tempo"],
    "selection_fragment_sets": [
        ("don't analyze region tempo", "change project tempo"),
    ],
    "suppress_future_prompt_labels": ["Don't show again"],
    "confirm_button_labels": ["OK", "Done", "Confirm", "Continue", "확인"],
}


def _normalize_label(value: str) -> str:
    return " ".join(value.replace("…", "...").replace("\u00a0", " ").split()).casefold()


def _escape_applescript(value: str) -> str:
    return value.replace("\\", "\\\\").replace('"', '\\"')


def _applescript_list(values: list[str] | tuple[str, ...]) -> str:
    return "{" + ", ".join(f'"{_escape_applescript(value)}"' for value in values) + "}"


def _script_prelude(markers: list[str] | tuple[str, ...]) -> str:
    return f"""
set modalMarkers to {_applescript_list(markers)}

on joinList(items)
    if (count of items) is 0 then return ""
    set oldDelims to AppleScript's text item delimiters
    set AppleScript's text item delimiters to "{LIST_SEPARATOR}"
    set joined to items as text
    set AppleScript's text item delimiters to oldDelims
    return joined
end joinList

on safeName(uiElement)
    try
        return (name of uiElement) as text
    on error
        try
            return (description of uiElement) as text
        on error
            try
                return (value of uiElement) as text
            on error
                return ""
            end try
        end try
    end try
end safeName

on namesOf(elements)
    set output to {{}}
    repeat with uiElement in elements
        set itemName to my safeName(uiElement)
        if itemName is not "" then set end of output to itemName
    end repeat
    return output
end namesOf

on namedStates(elements)
    set output to {{}}
    repeat with uiElement in elements
        set itemName to my safeName(uiElement)
        if itemName is "" then
            set itemName to "<unnamed>"
        end if
        try
            set itemValue to (value of uiElement) as text
        on error
            set itemValue to ""
        end try
        set end of output to itemName & "{STATE_SEPARATOR}" & itemValue
    end repeat
    return output
end namedStates

on namesForRole(containerElement, desiredRole)
    set output to {{}}
    try
        set containerItems to entire contents of containerElement
    on error
        return output
    end try
    repeat with uiElement in containerItems
        try
            if (role of uiElement) is desiredRole then
                set itemName to my safeName(uiElement)
                if itemName is not "" then set end of output to itemName
            end if
        end try
    end repeat
    return output
end namesForRole

on namedStatesForRole(containerElement, desiredRole)
    set output to {{}}
    try
        set containerItems to entire contents of containerElement
    on error
        return output
    end try
    repeat with uiElement in containerItems
        try
            if (role of uiElement) is desiredRole then
                set itemName to my safeName(uiElement)
                if itemName is "" then
                    set itemName to "<unnamed>"
                end if
                try
                    set itemValue to (value of uiElement) as text
                on error
                    set itemValue to ""
                end try
                set end of output to itemName & "{STATE_SEPARATOR}" & itemValue
            end if
        end try
    end repeat
    return output
end namedStatesForRole

on listContainsMarker(values, markers)
    repeat with rawValue in values
        set itemValue to rawValue as text
        repeat with rawMarker in markers
            set itemMarker to rawMarker as text
            if itemValue contains itemMarker then return true
        end repeat
    end repeat
    return false
end listContainsMarker

on modalContainer()
    tell application "System Events"
        if not (exists process "{_escape_applescript(PROCESS_NAME)}") then return missing value
        tell process "{_escape_applescript(PROCESS_NAME)}"
            repeat with candidateWindow in windows
                set windowTitle to ""
                try
                    set windowTitle to (name of candidateWindow) as text
                end try
                if my listContainsMarker({{windowTitle}}, modalMarkers) then return candidateWindow
                try
                    repeat with candidateSheet in sheets of candidateWindow
                        set candidateTexts to my namesForRole(candidateSheet, "AXStaticText")
                        set candidateButtons to my namesOf(buttons of candidateSheet)
                        set candidateCheckboxes to my namesOf(checkboxes of candidateSheet)
                        set candidateRadios to my namesForRole(candidateSheet, "AXRadioButton")
                        if my listContainsMarker(candidateTexts & candidateButtons & candidateCheckboxes & candidateRadios & {{windowTitle}}, modalMarkers) then
                            return candidateSheet
                        end if
                    end repeat
                end try
                try
                    set windowTexts to my namesForRole(candidateWindow, "AXStaticText")
                    set windowButtons to my namesOf(buttons of candidateWindow)
                    set windowCheckboxes to my namesOf(checkboxes of candidateWindow)
                    set windowRadios to my namesForRole(candidateWindow, "AXRadioButton")
                    if my listContainsMarker(windowTexts & windowButtons & windowCheckboxes & windowRadios & {{windowTitle}}, modalMarkers) then
                        return candidateWindow
                    end if
                end try
            end repeat
        end tell
    end tell
    return missing value
end modalContainer
"""


def _parse_lines(output: str) -> dict[str, str]:
    parsed: dict[str, str] = {}
    for line in output.splitlines():
        if "\t" not in line:
            continue
        key, value = line.split("\t", 1)
        parsed[key.strip()] = value.strip()
    return parsed


def _parse_named_states(value: str) -> list[dict[str, str]]:
    if not value:
        return []
    parsed: list[dict[str, str]] = []
    for item in value.split(LIST_SEPARATOR):
        if not item:
            continue
        if STATE_SEPARATOR in item:
            name, state = item.split(STATE_SEPARATOR, 1)
        else:
            name, state = item, ""
        parsed.append({"name": name, "value": state})
    return parsed


def _parse_snapshot(output: str) -> dict[str, Any]:
    parsed = _parse_lines(output)
    status = parsed.get("status", "error")
    snapshot: dict[str, Any] = {
        "status": status,
        "kind": parsed.get("kind", ""),
        "title": parsed.get("title", ""),
        "buttons": [item for item in parsed.get("buttons", "").split(LIST_SEPARATOR) if item],
        "checkboxes": _parse_named_states(parsed.get("checkboxes", "")),
        "radio_buttons": _parse_named_states(parsed.get("radio_buttons", "")),
        "static_texts": [item for item in parsed.get("static_texts", "").split(LIST_SEPARATOR) if item],
    }
    if "reason" in parsed:
        snapshot["reason"] = parsed["reason"]
    if "stderr" in parsed:
        snapshot["stderr"] = parsed["stderr"]
    return snapshot


def _is_truthy(value: str) -> bool:
    return _normalize_label(str(value)) in {"1", "true", "yes", "on", "selected"}


def _match_named_control(
    items: list[Any],
    exact_labels: list[str],
    fragment_sets: list[tuple[str, ...]] | None = None,
) -> dict[str, Any] | None:
    fragment_sets = fragment_sets or []
    normalized_exact = {_normalize_label(label): label for label in exact_labels}
    named_items: list[dict[str, Any]] = []
    for item in items:
        if isinstance(item, str):
            named_items.append({"name": item})
        elif isinstance(item, dict) and isinstance(item.get("name"), str):
            named_items.append(item)

    for item in named_items:
        normalized_name = _normalize_label(item["name"])
        if normalized_name in normalized_exact:
            return item

    for item in named_items:
        normalized_name = _normalize_label(item["name"])
        for fragments in fragment_sets:
            if all(fragment in normalized_name for fragment in fragments):
                return item
    return None


def _build_action_plan(snapshot: dict[str, Any], policy: dict[str, Any]) -> dict[str, Any]:
    decision: dict[str, Any] = {"policy_id": policy["policy_id"]}
    steps: list[dict[str, Any]] = []

    selection = _match_named_control(
        snapshot.get("radio_buttons", []),
        policy.get("selection_labels", []),
        policy.get("selection_fragment_sets", []),
    )
    selection_role = "radio button"
    if selection is None:
        selection = _match_named_control(
            snapshot.get("checkboxes", []),
            policy.get("selection_labels", []),
            policy.get("selection_fragment_sets", []),
        )
        selection_role = "checkbox"
    if selection is None:
        selection = _match_named_control(
            snapshot.get("buttons", []),
            policy.get("selection_labels", []),
            policy.get("selection_fragment_sets", []),
        )
        selection_role = "button"
    if selection is None:
        return {
            "status": "blocked",
            "reason": "selection_control_missing",
            "decision": decision,
        }

    decision["selection"] = selection["name"]
    decision["selection_role"] = selection_role
    selection_value = selection.get("value", "")
    decision["selection_already_active"] = _is_truthy(selection_value)
    if selection_role != "button" and not decision["selection_already_active"]:
        steps.append(
            {
                "role": selection_role,
                "name": selection["name"],
                "purpose": "select_keep_project_tempo_no_analysis",
            }
        )

    suppress_checkbox = _match_named_control(
        snapshot.get("checkboxes", []),
        policy.get("suppress_future_prompt_labels", []),
    )
    if suppress_checkbox is None:
        decision["suppress_future_prompts"] = "checkbox_unavailable"
    elif _is_truthy(suppress_checkbox.get("value", "")):
        decision["suppress_future_prompts"] = "already_enabled"
    else:
        decision["suppress_future_prompts"] = "requested"
        steps.append(
            {
                "role": "checkbox",
                "name": suppress_checkbox["name"],
                "purpose": "suppress_future_prompt",
            }
        )

    if selection_role == "button":
        decision["confirm"] = selection["name"]
        decision["confirm_strategy"] = "selection_button"
        return {"status": "actionable", "decision": decision, "steps": steps}

    confirm_button = _match_named_control(
        snapshot.get("buttons", []),
        policy.get("confirm_button_labels", []),
    )
    if confirm_button is None:
        buttons = snapshot.get("buttons", [])
        if len(buttons) == 1:
            confirm_button = {"name": buttons[0]}
            decision["confirm_strategy"] = "single_button_fallback"
        else:
            return {
                "status": "blocked",
                "reason": "confirm_button_missing",
                "decision": decision,
            }
    else:
        decision["confirm_strategy"] = "named_button"

    decision["confirm"] = confirm_button["name"]
    steps.append(
        {
            "role": "button",
            "name": confirm_button["name"],
            "purpose": "confirm_modal_policy",
        }
    )
    return {"status": "actionable", "decision": decision, "steps": steps}


class SystemEventsFreeTempoModalRunner:
    """Drive Logic's modal via System Events osascript UI scripting."""

    def __init__(
        self,
        markers: tuple[str, ...] = MODAL_MARKERS,
        run=subprocess.run,
    ) -> None:
        self.markers = markers
        self._run = run

    def _osascript(self, source: str, timeout: float = 12.0) -> subprocess.CompletedProcess[str]:
        return self._run(
            ["/usr/bin/osascript", "-l", "JavaScript"],
            input=source,
            text=True,
            capture_output=True,
            check=False,
            timeout=timeout,
        )

    def _jxa_prelude(self) -> str:
        markers_json = json.dumps(list(self.markers), ensure_ascii=False)
        return f"""
const MODAL_MARKERS = {markers_json};

function safe(fn, fallback) {{
  try {{
    return fn();
  }} catch (error) {{
    return fallback;
  }}
}}

function str(value) {{
  return value === undefined || value === null ? "" : String(value);
}}

function safeName(item) {{
  const name = safe(() => item.name(), "");
  if (name) return str(name);
  const description = safe(() => item.description(), "");
  if (description) return str(description);
  return str(safe(() => item.value(), ""));
}}

function namesOf(collection) {{
  const output = [];
  for (let index = 0; index < collection.length; index += 1) {{
    const name = safeName(collection[index]);
    if (name) output.push(name);
  }}
  return output;
}}

function namedStates(collection) {{
  const output = [];
  for (let index = 0; index < collection.length; index += 1) {{
    const item = collection[index];
    const name = safeName(item) || "<unnamed>";
    output.push({{ name, value: str(safe(() => item.value(), "")) }});
  }}
  return output;
}}

function containsMarker(values) {{
  return values.some((value) => MODAL_MARKERS.some((marker) => str(value).includes(marker)));
}}

function collection(container, roleName) {{
  if (roleName === "button") return safe(() => container.buttons(), []);
  if (roleName === "checkbox") return safe(() => container.checkboxes(), []);
  if (roleName === "radio button") return safe(() => container.radioButtons(), []);
  if (roleName === "static text") return safe(() => container.staticTexts(), []);
  return [];
}}

function findModal() {{
  const systemEvents = Application("System Events");
  const process = systemEvents.processes.byName("Logic Pro");
  if (!safe(() => process.exists(), false)) return null;
  const windows = safe(() => process.windows(), []);
  for (let windowIndex = 0; windowIndex < windows.length; windowIndex += 1) {{
    const win = windows[windowIndex];
    const title = str(safe(() => win.name(), ""));
    if (containsMarker([title])) {{
      return {{ kind: "window", title, container: win }};
    }}

    const sheets = safe(() => win.sheets(), []);
    for (let sheetIndex = 0; sheetIndex < sheets.length; sheetIndex += 1) {{
      const sheet = sheets[sheetIndex];
      const labels = [title].concat(
        namesOf(collection(sheet, "static text")),
        namesOf(collection(sheet, "button")),
        namesOf(collection(sheet, "checkbox")),
        namesOf(collection(sheet, "radio button"))
      );
      if (containsMarker(labels)) {{
        const sheetTitle = str(safe(() => sheet.name(), title)) || title;
        return {{ kind: "sheet", title: sheetTitle, container: sheet }};
      }}
    }}

    const windowLabels = [title].concat(
      namesOf(collection(win, "static text")),
      namesOf(collection(win, "button")),
      namesOf(collection(win, "checkbox")),
      namesOf(collection(win, "radio button"))
    );
    if (containsMarker(windowLabels)) {{
      return {{ kind: "window", title, container: win }};
    }}
  }}
  return null;
}}
"""

    def _json_result(self, result: subprocess.CompletedProcess[str]) -> dict[str, Any]:
        try:
            parsed = json.loads(result.stdout.strip() or "{}")
        except json.JSONDecodeError:
            return {
                "status": "error",
                "reason": "invalid_jxa_output",
                "stderr": (result.stderr or "").strip(),
                "stdout": (result.stdout or "").strip(),
            }
        return parsed if isinstance(parsed, dict) else {"status": "error", "reason": "invalid_jxa_output"}

    def detect(self) -> dict[str, Any]:
        script = self._jxa_prelude() + """
const target = findModal();
if (!target) {
  JSON.stringify({ status: "not_present" });
} else {
  JSON.stringify({
    status: "present",
    kind: target.kind,
    title: target.title,
    buttons: namesOf(collection(target.container, "button")),
    checkboxes: namedStates(collection(target.container, "checkbox")),
    radio_buttons: namedStates(collection(target.container, "radio button")),
    static_texts: namesOf(collection(target.container, "static text")),
  });
}
"""
        try:
            result = self._osascript(script)
        except (FileNotFoundError, subprocess.TimeoutExpired) as error:
            return {"status": "error", "reason": "osascript_failed", "stderr": str(error)}
        if result.returncode != 0:
            return {
                "status": "error",
                "reason": "osascript_failed",
                "stderr": (result.stderr or "").strip(),
            }
        return self._json_result(result)

    def click(self, role: str, name: str) -> dict[str, Any]:
        script = self._jxa_prelude() + f"""
const targetRole = {json.dumps(role, ensure_ascii=False)};
const targetName = {json.dumps(name, ensure_ascii=False)};
const target = findModal();

if (!target) {{
  JSON.stringify({{ status: "not_present" }});
}} else {{
  const candidates = collection(target.container, targetRole);
  let matched = null;
  for (let index = 0; index < candidates.length; index += 1) {{
    if (safeName(candidates[index]) === targetName) {{
      matched = candidates[index];
      break;
    }}
  }}

  if (!matched) {{
    JSON.stringify({{ status: "error", message: "control not found" }});
  }} else {{
    try {{
      matched.click();
      JSON.stringify({{ status: "clicked" }});
    }} catch (clickError) {{
      try {{
        const actions = safe(() => matched.actions(), []);
        if (actions.length > 0) {{
          actions[0].perform();
          JSON.stringify({{ status: "clicked" }});
        }} else {{
          JSON.stringify({{ status: "error", message: str(clickError) }});
        }}
      }} catch (fallbackError) {{
        JSON.stringify({{ status: "error", message: str(fallbackError) }});
      }}
    }}
  }}
}}
"""
        try:
            result = self._osascript(script)
        except (FileNotFoundError, subprocess.TimeoutExpired) as error:
            return {
                "status": "error",
                "role": role,
                "name": name,
                "reason": "osascript_failed",
                "message": str(error),
            }
        parsed = self._json_result(result)
        payload = {
            "status": parsed.get("status", "error"),
            "role": role,
            "name": name,
        }
        if "message" in parsed:
            payload["message"] = parsed["message"]
        if result.returncode != 0 and payload["status"] == "error":
            payload["message"] = (result.stderr or "").strip() or payload.get("message", "")
        return payload


def detect_free_tempo_modal(
    runner: SystemEventsFreeTempoModalRunner | None = None,
) -> dict[str, Any]:
    return (runner or SystemEventsFreeTempoModalRunner()).detect()


def resolve_free_tempo_modal(
    runner: SystemEventsFreeTempoModalRunner | None = None,
    policy: dict[str, Any] | None = None,
    pause=time.sleep,
) -> dict[str, Any]:
    active_runner = runner or SystemEventsFreeTempoModalRunner()
    active_policy = deepcopy(policy or DEFAULT_FREE_TEMPO_POLICY)
    before = active_runner.detect()
    result: dict[str, Any] = {
        "policy_id": active_policy["policy_id"],
        "before": before,
        "actions": [],
        "decision": {},
    }

    if before.get("status") != "present":
        result["status"] = before.get("status", "error")
        if before.get("reason"):
            result["reason"] = before["reason"]
        return result

    plan = _build_action_plan(before, active_policy)
    result["decision"] = plan.get("decision", {})
    if plan.get("status") != "actionable":
        result["status"] = "blocked"
        result["reason"] = plan.get("reason", "plan_blocked")
        return result

    for step in plan["steps"]:
        click_result = active_runner.click(step["role"], step["name"])
        click_result["purpose"] = step["purpose"]
        result["actions"].append(click_result)
        if click_result.get("status") != "clicked":
            result["status"] = "blocked"
            result["reason"] = "click_failed"
            result["after"] = active_runner.detect()
            return result
        pause(0.2)

    after = active_runner.detect()
    result["after"] = after
    if after.get("status") == "present":
        result["status"] = "blocked"
        result["reason"] = "modal_still_visible"
    elif after.get("status") == "error":
        result["status"] = "error"
        result["reason"] = after.get("reason", "postcheck_failed")
    else:
        result["status"] = "dismissed"
    return result


def _main(argv: list[str]) -> int:
    command = argv[1] if len(argv) > 1 else "detect"
    if command == "detect":
        payload = detect_free_tempo_modal()
    elif command == "resolve":
        payload = resolve_free_tempo_modal()
    else:
        print("usage: logic_free_tempo_modal.py [detect|resolve]", file=sys.stderr)
        return 2
    print(json.dumps(payload, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(_main(sys.argv))
