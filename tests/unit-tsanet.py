#!/usr/bin/env python3

#
# Copyright (C) 2026 tebbi
# SPDX-License-Identifier: GPL-3.0-or-later
#

"""Unit tests for imageroot/pypkg/tsanet.py (the client IP allowlist helpers).

Pure logic, no node required. Run directly:

    python3 tests/unit-tsanet.py

These cover the allowlist round-trip and validation that configure-module and
restore-module rely on (clean-coding developer tests / CSV OQ evidence for
URS-1).
"""

import os
import sys
import unittest

sys.path.insert(
    0, os.path.join(os.path.dirname(__file__), "..", "imageroot", "pypkg")
)

import tsanet  # noqa: E402


class ParseAllowlist(unittest.TestCase):
    def test_empty_and_none(self):
        self.assertEqual(tsanet.parse_allowlist(""), [])
        self.assertEqual(tsanet.parse_allowlist(None), [])

    def test_json_array(self):
        self.assertEqual(
            tsanet.parse_allowlist('["10.0.0.0/8", " 1.2.3.4 ", ""]'),
            ["10.0.0.0/8", "1.2.3.4"],
        )

    def test_malformed_is_open(self):
        # A hand-edited / legacy value must never break route configuration.
        self.assertEqual(tsanet.parse_allowlist("not json"), [])
        self.assertEqual(tsanet.parse_allowlist('{"a": 1}'), [])
        self.assertEqual(tsanet.parse_allowlist("42"), [])

    def test_round_trip(self):
        entries = ["10.0.0.0/8", "1.2.3.4"]
        self.assertEqual(
            tsanet.parse_allowlist(tsanet.format_allowlist(entries)), entries
        )


class NormalizeAllowlist(unittest.TestCase):
    def test_trim_dedup_keep_order(self):
        self.assertEqual(
            tsanet.normalize_allowlist(["b", "a", "b", " a ", ""]), ["b", "a"]
        )

    def test_none(self):
        self.assertEqual(tsanet.normalize_allowlist(None), [])


class ValidateAllowlist(unittest.TestCase):
    def test_all_valid(self):
        self.assertEqual(
            tsanet.validate_allowlist(
                ["10.0.0.0/8", "1.2.3.4", "2001:db8::/32", "::1"]
            ),
            [],
        )

    def test_reports_invalid(self):
        self.assertEqual(
            tsanet.validate_allowlist(
                ["10.0.0.0/8", "nope", "999.1.1.1", "1.2.3.4/33"]
            ),
            ["nope", "999.1.1.1", "1.2.3.4/33"],
        )

    def test_host_bits_allowed(self):
        # Traefik's sourceRange accepts a CIDR with host bits set.
        self.assertEqual(tsanet.validate_allowlist(["192.0.2.5/24"]), [])


if __name__ == "__main__":
    unittest.main(verbosity=2)
