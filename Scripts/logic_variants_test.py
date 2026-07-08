"""Contract tests for Scripts/logic_variants.py (manifest-driven bundle/process names)."""

from __future__ import annotations

import os
import unittest

import logic_variants


class LogicVariantsPolicyTests(unittest.TestCase):
    def test_manifest_bundle_ids_desktop_before_creator_studio(self):
        bundle_ids = logic_variants.manifest_bundle_ids_in_order()
        self.assertEqual(bundle_ids[0], "com.apple.logic10")
        self.assertEqual(bundle_ids[1], "com.apple.mobilelogic")

    def test_manifest_process_names_and_install_paths_present(self):
        variants = logic_variants.manifest_variants()
        self.assertEqual(variants[0]["process_name"], "Logic Pro")
        self.assertEqual(variants[1]["process_name"], "Logic Pro Creator Studio")
        self.assertTrue(all(v["default_install_path"].endswith(".app") for v in variants))

    def test_process_name_map_keys_match_manifest(self):
        self.assertEqual(
            set(logic_variants.process_name_by_bundle_id()),
            set(logic_variants.manifest_bundle_ids_in_order()),
        )

    def test_default_priority_matches_manifest(self):
        previous = os.environ.pop("LOGIC_PRO_BUNDLE_ID", None)
        try:
            self.assertEqual(
                logic_variants.bundle_ids_in_priority_order(),
                logic_variants.manifest_bundle_ids_in_order(),
            )
        finally:
            if previous is not None:
                os.environ["LOGIC_PRO_BUNDLE_ID"] = previous

    def test_forced_bundle_id_overrides_priority(self):
        previous = os.environ.get("LOGIC_PRO_BUNDLE_ID")
        os.environ["LOGIC_PRO_BUNDLE_ID"] = "com.example.custom"
        try:
            self.assertEqual(logic_variants.bundle_ids_in_priority_order(), ("com.example.custom",))
        finally:
            if previous is None:
                os.environ.pop("LOGIC_PRO_BUNDLE_ID", None)
            else:
                os.environ["LOGIC_PRO_BUNDLE_ID"] = previous

    def test_jxa_find_process_snippet_includes_all_manifest_process_names(self):
        snippet = logic_variants.jxa_find_process_snippet()
        for process_name in logic_variants.logic_app_names():
            self.assertIn(process_name, snippet)

    def test_process_name_for_unknown_bundle_returns_bundle_id(self):
        self.assertEqual(
            logic_variants.process_name_for_bundle_id("com.example.custom"),
            "com.example.custom",
        )


if __name__ == "__main__":
    unittest.main()
