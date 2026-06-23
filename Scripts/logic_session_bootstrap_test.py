#!/usr/bin/env python3
import unittest

from logic_session_bootstrap import (
    BootstrapConfig,
    FreshSessionAssessment,
    UISnapshot,
    detect_language,
    evaluate_fresh_session,
)


def make_config(expected_language="en", max_tracks=1):
    return BootstrapConfig(
        expected_language=expected_language,
        hide_apps=(),
        max_tracks=max_tracks,
        allow_launch=True,
        allow_new_project=True,
        confirm_new_track_dialog=True,
        timeout_sec=8.0,
        poll_interval_sec=0.35,
    )


def make_ui(**overrides):
    base = UISnapshot(
        frontmost_app="Logic Pro",
        logic_window_names=["Untitled 1 - Tracks"],
        logic_menu_items=["File", "Edit", "Track", "Navigate", "Record", "Mix", "View", "Window", "Help"],
        detected_language="en",
        system_events_error=None,
        project_picker_visible=False,
        new_track_dialog_visible=False,
    )
    values = base.__dict__.copy()
    values.update(overrides)
    return UISnapshot(**values)


def make_health(**overrides):
    health = {
        "logic_pro_running": True,
        "logic_pro_has_window": True,
        "logic_pro_has_document": True,
        "permissions": {
            "accessibility": True,
            "post_event_access": True,
        },
    }
    health.update(overrides)
    return health


def make_project(track_count=1, source="ax_live", name="Untitled 1"):
    return {
        "source": source,
        "data": {
            "name": name,
            "trackCount": track_count,
            "source": source,
        },
    }


def make_tracks(count=1, placeholder_count=0, ax_occluded=False):
    rows = []
    for index in range(count):
        rows.append(
            {
                "id": index,
                "name": f"Track {index + 1}",
                "placeholder": index < placeholder_count,
            }
        )
    return {
        "source": "ax_live",
        "ax_occluded": ax_occluded,
        "data": rows,
    }


class DetectLanguageTests(unittest.TestCase):
    def test_detects_english_menu(self):
        self.assertEqual(detect_language(["File", "Edit", "Track"]), "en")

    def test_detects_korean_menu(self):
        self.assertEqual(detect_language(["파일", "편집", "트랙"]), "ko")

    def test_returns_none_for_unknown_menu(self):
        self.assertIsNone(detect_language(["Archivo", "Editar", "Pista"]))


class EvaluateFreshSessionTests(unittest.TestCase):
    def assert_reason(self, assessment: FreshSessionAssessment, reason: str):
        self.assertFalse(assessment.ok)
        self.assertEqual(assessment.reason, reason)

    def test_accepts_fresh_single_track_project(self):
        assessment = evaluate_fresh_session(
            ui=make_ui(),
            health=make_health(),
            project_payload=make_project(track_count=1),
            tracks_payload=make_tracks(count=1),
            region_count=0,
            config=make_config(),
        )
        self.assertTrue(assessment.ok)
        self.assertEqual(assessment.inferred_track_count, 1)

    def test_blocks_language_mismatch(self):
        assessment = evaluate_fresh_session(
            ui=make_ui(detected_language="ko"),
            health=make_health(),
            project_payload=make_project(track_count=1),
            tracks_payload=make_tracks(count=1),
            region_count=0,
            config=make_config(expected_language="en"),
        )
        self.assert_reason(assessment, "language_mismatch")

    def test_blocks_project_picker(self):
        assessment = evaluate_fresh_session(
            ui=make_ui(project_picker_visible=True),
            health=make_health(),
            project_payload=make_project(track_count=1),
            tracks_payload=make_tracks(count=1),
            region_count=0,
            config=make_config(),
        )
        self.assert_reason(assessment, "project_picker_visible")

    def test_blocks_placeholder_tracks(self):
        assessment = evaluate_fresh_session(
            ui=make_ui(),
            health=make_health(),
            project_payload=make_project(track_count=1),
            tracks_payload=make_tracks(count=1, placeholder_count=1),
            region_count=0,
            config=make_config(),
        )
        self.assert_reason(assessment, "tracks_not_live")

    def test_blocks_occluded_tracks(self):
        assessment = evaluate_fresh_session(
            ui=make_ui(),
            health=make_health(),
            project_payload=make_project(track_count=1),
            tracks_payload=make_tracks(count=1, ax_occluded=True),
            region_count=0,
            config=make_config(),
        )
        self.assert_reason(assessment, "ax_occluded")

    def test_blocks_polluted_session_when_track_count_exceeds_budget(self):
        assessment = evaluate_fresh_session(
            ui=make_ui(),
            health=make_health(),
            project_payload=make_project(track_count=3),
            tracks_payload=make_tracks(count=3),
            region_count=0,
            config=make_config(max_tracks=1),
        )
        self.assert_reason(assessment, "polluted_session")

    def test_blocks_existing_regions(self):
        assessment = evaluate_fresh_session(
            ui=make_ui(),
            health=make_health(),
            project_payload=make_project(track_count=1),
            tracks_payload=make_tracks(count=1),
            region_count=2,
            config=make_config(),
        )
        self.assert_reason(assessment, "existing_regions_present")

    def test_blocks_system_events_probe_failure_before_frontmost(self):
        assessment = evaluate_fresh_session(
            ui=make_ui(
                frontmost_app=None,
                logic_window_names=[],
                logic_menu_items=[],
                detected_language=None,
                system_events_error="osascript_exit_1: Not authorized to send Apple events to System Events. (-1743)",
            ),
            health=make_health(),
            project_payload=make_project(track_count=1),
            tracks_payload=make_tracks(count=1),
            region_count=0,
            config=make_config(),
        )
        self.assert_reason(assessment, "system_events_unavailable")
        self.assertIn("System Events", assessment.hint or "")


if __name__ == "__main__":
    unittest.main()
