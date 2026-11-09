"""Tests for resolve_akmods_candidate.py.

Run: python3 -m unittest discover -s .github/scripts/tests
"""
import io
import json
import os
import sys
import unittest
from contextlib import redirect_stderr, redirect_stdout
from unittest import mock

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
import resolve_akmods_candidate as m  # noqa: E402


def cfg(version="44.20261107.1", kernel="7.2.15-200.fc44.x86_64"):
    labels = {}
    if version is not None:
        labels["org.opencontainers.image.version"] = version
    if kernel is not None:
        labels["ostree.linux"] = kernel
    return {"config": {"Labels": labels}}


def run_main(argv, stdin_text):
    out, err = io.StringIO(), io.StringIO()
    with mock.patch("sys.stdin", io.StringIO(stdin_text)), \
            redirect_stdout(out), redirect_stderr(err):
        rc = m.main(argv)
    return rc, out.getvalue(), err.getvalue()


class ResolveTests(unittest.TestCase):
    def test_f44(self):
        self.assertEqual(m.resolve("main", cfg()),
                         ("44", "7.2.15-200.fc44", "main-44-7.2.15-200.fc44"))

    def test_f45_crossing_needs_no_edit(self):
        c = cfg("45.20261107.1", "7.2.15-300.fc45.x86_64")
        self.assertEqual(m.resolve("main", c)[2], "main-45-7.2.15-300.fc45")

    def test_other_flavor(self):
        self.assertEqual(m.resolve("coreos-stable", cfg())[2],
                         "coreos-stable-44-7.2.15-200.fc44")

    def test_major_disagreement_fails(self):
        with self.assertRaisesRegex(m.ResolveError, "disagree"):
            m.resolve("main", cfg("45.20261107.1", "7.2.15-200.fc44.x86_64"))

    def test_missing_version_label_fails(self):
        with self.assertRaisesRegex(m.ResolveError, "org.opencontainers.image.version"):
            m.resolve("main", cfg(version=None))

    def test_missing_kernel_label_fails(self):
        with self.assertRaisesRegex(m.ResolveError, "ostree.linux"):
            m.resolve("main", cfg(kernel=None))

    def test_non_numeric_version_fails(self):
        with self.assertRaises(m.ResolveError):
            m.resolve("main", cfg(version="rawhide.20261107.1"))
        with self.assertRaises(m.ResolveError):
            m.resolve("main", cfg(version="testing-44.20261107.1"))

    def test_kernel_without_fc_or_arch_fails(self):
        for bad in ("7.2.15-200.fc44", "7.2.15-200.x86_64", "7.2.15-200.el10.x86_64", ""):
            with self.subTest(kernel=bad), self.assertRaises(m.ResolveError):
                m.resolve("main", cfg(kernel=bad))

    def test_empty_or_missing_config_fails(self):
        for bad in ({}, {"config": {}}, {"config": {"Labels": None}}, {"config": None},
                    {"config": {"Labels": []}}, {"config": []}, [], None, "x", 5):
            with self.subTest(cfg=bad), self.assertRaises(m.ResolveError):
                m.resolve("main", bad)

    def test_present_but_non_string_labels_fail_cleanly(self):
        for key in ("org.opencontainers.image.version", "ostree.linux"):
            for bad in (None, 44, ["44"], {"a": 1}, True):
                c = cfg()
                c["config"]["Labels"][key] = bad
                with self.subTest(key=key, value=bad), self.assertRaises(m.ResolveError):
                    m.resolve("main", c)

    def test_other_kernel_shapes(self):
        self.assertEqual(
            m.resolve("main", cfg("45.20261107.1", "7.3.0-0.rc1.fc45.aarch64")),
            ("45", "7.3.0-0.rc1.fc45", "main-45-7.3.0-0.rc1.fc45"))

    def test_last_fc_segment_wins(self):
        # A dist tag can repeat; the release is the LAST .fcNN, followed only by the arch.
        self.assertEqual(
            m.resolve("main", cfg("45.20261107.1", "7.2.15-200.fc44.fc45.x86_64"))[:2],
            ("45", "7.2.15-200.fc44.fc45"))

    def test_bad_flavor_fails(self):
        # "main-44" is the old value of AKMODS_TAG; as a flavor it would double the release.
        for bad in ("", "Main", "main/../x", "main-44", "-main", "main_44", "ma in"):
            with self.subTest(flavor=bad), self.assertRaises(m.ResolveError):
                m.resolve(bad, cfg())


class MainTests(unittest.TestCase):
    def test_prints_only_the_tag(self):
        rc, out, err = run_main(["x", "main"], json.dumps(cfg()))
        self.assertEqual((rc, out, err), (0, "main-44-7.2.15-200.fc44\n", ""))

    def test_error_goes_to_stderr_with_exit_1(self):
        rc, out, err = run_main(["x", "main"], json.dumps(cfg(kernel="bogus")))
        self.assertEqual((rc, out), (1, ""))
        self.assertIn("ostree.linux", err)

    def test_null_label_exits_1_not_a_traceback(self):
        c = cfg()
        c["config"]["Labels"]["ostree.linux"] = None
        rc, out, err = run_main(["x", "main"], json.dumps(c))
        self.assertEqual((rc, out), (1, ""))
        self.assertNotIn("Traceback", err)
        self.assertIn("ostree.linux", err)

    def test_invalid_json_exits_1(self):
        rc, out, err = run_main(["x", "main"], "not json")
        self.assertEqual((rc, out), (1, ""))
        self.assertIn("not valid JSON", err)

    def test_usage(self):
        rc, _, err = run_main(["x"], "{}")
        self.assertEqual(rc, 2)
        self.assertIn("usage", err)


if __name__ == "__main__":
    unittest.main()
