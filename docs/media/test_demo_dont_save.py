#!/usr/bin/env python3
"""Tests for the "Don't Save" candidate-expansion policy (issue #132).

These tests pin the byte-exact behaviour that broke in #132: the candidate list
must gain the *curly* "Don’t Save" (U+2019) that Logic actually renders, not just
the straight "Don't Save" (U+0027).
"""

from __future__ import annotations

import unittest

from demo_dont_save import (
    CURLY_DONT_SAVE,
    DELETE_LABEL,
    STRAIGHT_DONT_SAVE,
    expand_dont_save_candidates,
)


class ExpandDontSaveCandidatesTests(unittest.TestCase):
    def test_appends_curly_dont_save_and_delete(self) -> None:
        result = expand_dont_save_candidates(["저장 안 함", "Don't Save", "생성"])
        # The curly U+2019 spelling Logic actually renders must be present.
        self.assertIn(CURLY_DONT_SAVE, result)
        self.assertIn("Delete", result)
        # Originals preserved verbatim and in order, fallbacks appended after.
        self.assertEqual(result[:3], ["저장 안 함", "Don't Save", "생성"])
        self.assertEqual(result[3:], [CURLY_DONT_SAVE, DELETE_LABEL])

    def test_appended_apostrophe_is_byte_level_u2019(self) -> None:
        result = expand_dont_save_candidates(["저장 안 함", "Don't Save", "생성"])
        result_joined = "".join(result)
        # Byte-level: the curly RIGHT SINGLE QUOTATION MARK must literally appear.
        self.assertIn("’", result_joined)
        self.assertIn("’", result_joined)
        # And the appended spelling carries U+2019, not the U+0027 it started with.
        appended_curly = result[3]
        self.assertIn("’", appended_curly)
        self.assertNotIn("'", appended_curly)

    def test_straight_input_has_only_u0027(self) -> None:
        # Guards the premise of #132: the seed straight title carries U+0027 only.
        self.assertIn("'", STRAIGHT_DONT_SAVE)
        self.assertNotIn("’", STRAIGHT_DONT_SAVE)

    def test_idempotent_when_curly_already_present(self) -> None:
        already = ["저장 안 함", "Don't Save", CURLY_DONT_SAVE, "Delete"]
        result = expand_dont_save_candidates(already)
        # No double-append: already-present curly + Delete are not duplicated.
        self.assertEqual(result, already)
        self.assertEqual(result.count(CURLY_DONT_SAVE), 1)
        self.assertEqual(result.count(DELETE_LABEL), 1)

    def test_idempotent_on_repeated_application(self) -> None:
        once = expand_dont_save_candidates(["Don't Save"])
        twice = expand_dont_save_candidates(once)
        self.assertEqual(once, twice)

    def test_unrelated_list_unchanged(self) -> None:
        unrelated = ["저장 안 함", "생성", "Cancel"]
        result = expand_dont_save_candidates(unrelated)
        self.assertEqual(result, unrelated)
        self.assertNotIn(CURLY_DONT_SAVE, result)
        self.assertNotIn(DELETE_LABEL, result)

    def test_delete_appended_even_if_already_curly_present_but_no_delete(self) -> None:
        # Straight present, curly present, Delete absent -> only Delete appended.
        result = expand_dont_save_candidates(["Don't Save", CURLY_DONT_SAVE])
        self.assertEqual(result, ["Don't Save", CURLY_DONT_SAVE, DELETE_LABEL])

    def test_input_iterable_not_mutated(self) -> None:
        source = ["Don't Save"]
        expand_dont_save_candidates(source)
        self.assertEqual(source, ["Don't Save"])


if __name__ == "__main__":
    unittest.main()
