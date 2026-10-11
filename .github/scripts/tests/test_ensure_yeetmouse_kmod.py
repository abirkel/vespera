"""Tests for ensure_yeetmouse_kmod.py. Run: python3 -m unittest discover -s .github/scripts/tests"""
import gzip
import hashlib
import json
import os
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
import ensure_yeetmouse_kmod as m  # noqa: E402

KVER = "7.2.9-200.fc44.x86_64"
EVR = ("0", "0^20260803git78dcd0d", "1.fc44")
REPO = "https://copr.example/results/abirkel/yeetmouse/fedora-44-x86_64/"
API = "https://api.example/repos/abirkel/yeetmouse-rpm"


def pkg(name, arch, evr=EVR):
    e, v, r = evr
    return (f'<package type="rpm"><name>{name}</name><arch>{arch}</arch>'
            f'<version epoch="{e}" ver="{v}" rel="{r}"/></package>')


FULL = [pkg(f"kmod-yeetmouse-{KVER}", "x86_64"), pkg("yeetmouse-kmod-common", "noarch"),
        pkg("yeetmouse", "x86_64")]
NO_KMOD = FULL[1:]


def primary(pkgs, compress=gzip.compress):
    xml = ('<?xml version="1.0"?><metadata xmlns="http://linux.duke.edu/metadata/common" '
           f'packages="{len(pkgs)}">' + "".join(pkgs) + "</metadata>").encode()
    return compress(xml)


def repomd(data, href):
    digest = hashlib.sha256(data).hexdigest()
    return (f'<repomd xmlns="http://linux.duke.edu/metadata/repo"><revision>{digest[:6]}'
            f'</revision><data type="primary"><checksum type="sha256">{digest}</checksum>'
            f'<location href="{href}"/></data></repomd>').encode()


class Clock:
    def __init__(self):
        self.t = 0.0

    def __call__(self):
        return self.t

    def sleep(self, s):
        assert s >= 0
        self.t += s


class World:
    """Fake COPR + GitHub. `timeline` maps a time to the package list visible from then."""

    def __init__(self, clock, timeline, active=None, runs=None, dispatch_status=200):
        self.clock = clock
        self.timeline = sorted(timeline.items())
        self.active = active or {}     # status -> list of runs
        self.runs = runs or {}         # run id -> list of (from_time, run dict)
        self.jobs = {}
        self.dispatch_status = dispatch_status
        self.dispatched = []
        self.next_id = 100
        self.on_dispatch = None
        self.repomd_fail_until = -1

    def pkgs(self):
        cur = []
        for t, p in self.timeline:
            if self.clock() >= t:
                cur = p
        return cur

    def __call__(self, method, url, headers, body=None):
        if url.startswith(REPO + "repodata/repomd.xml"):
            assert headers.get("Cache-Control") == "no-cache"
            if self.clock() < self.repomd_fail_until:
                return m.Response(503, b"")
            data = primary(self.pkgs())
            self._primary = data
            return m.Response(200, repomd(data, "repodata/x-primary.xml.gz"))
        if url == REPO + "repodata/x-primary.xml.gz":
            return m.Response(200, self._primary)
        if method == "POST" and url.endswith("/dispatches"):
            assert json.loads(body) == {"ref": "main", "return_run_details": True}
            assert headers["Authorization"] == "Bearer tok"
            if self.dispatch_status != 200:
                return m.Response(self.dispatch_status, b"{}")
            rid = self.next_id
            self.next_id += 1
            self.dispatched.append((self.clock(), rid))
            if self.on_dispatch:
                self.on_dispatch(rid)
            return m.Response(200, json.dumps({"workflow_run_id": rid}).encode())
        if "/runs?status=" in url:
            status = url.split("status=")[1].split("&")[0]
            return m.Response(200, json.dumps(
                {"workflow_runs": self.active.get(status, [])}).encode())
        if url.startswith(API + "/actions/runs/") and url.endswith("/jobs"):
            rid = int(url.split("/")[-2])
            return m.Response(200, json.dumps({"jobs": self.jobs.get(rid, [])}).encode())
        if url.startswith(API + "/actions/runs/"):
            rid = int(url.rsplit("/", 1)[1])
            cur = {"status": "queued"}
            for t, r in self.runs.get(rid, []):
                if self.clock() >= t:
                    cur = r
            return m.Response(200, json.dumps(cur).encode())
        raise AssertionError(f"unexpected {method} {url}")


def cfg(**kw):
    c = m.Config(kver=KVER, fedora="44", arch="x86_64",
                 copr_base="https://copr.example/results/abirkel/yeetmouse",
                 gh_api="https://api.example", token="tok")
    for k, v in kw.items():
        setattr(c, k, v)
    return c


def done(conclusion):
    return {"status": "completed", "conclusion": conclusion}


def run(world, clock, c):
    return m.ensure(c, http=world, clock=clock, sleep=clock.sleep, wall=clock)


class Tests(unittest.TestCase):
    def setUp(self):
        self.clock = Clock()

    def test_present_returns_at_once_without_dispatch(self):
        w = World(self.clock, {0: FULL})
        self.assertIn("are in COPR", run(w, self.clock, cfg()))
        self.assertEqual(w.dispatched, [])
        self.assertEqual(self.clock.t, 0)

    def test_missing_kmod_common_counts_as_missing(self):
        w = World(self.clock, {0: [FULL[0], FULL[2]]})
        self.assertEqual(m.missing_packages(cfg(), m.read_repo(cfg(), w, 0)),
                         [f"yeetmouse-kmod-common at 0:{EVR[1]}-{EVR[2]}"])

    def test_kmod_common_at_other_release_counts_as_missing(self):
        w = World(self.clock, {0: [FULL[0], pkg("yeetmouse-kmod-common", "noarch",
                                                 ("0", EVR[1], "2.fc44")), FULL[2]]})
        self.assertEqual(len(m.missing_packages(cfg(), m.read_repo(cfg(), w, 0))), 1)

    def test_missing_without_token_fails_fast(self):
        w = World(self.clock, {0: NO_KMOD})
        with self.assertRaisesRegex(m.Fatal, "no YEETMOUSE_DISPATCH_TOKEN"):
            run(w, self.clock, cfg(token=""))
        self.assertEqual(self.clock.t, 0)

    def test_dispatch_then_package_appears(self):
        w = World(self.clock, {0: NO_KMOD, 900: FULL})
        w.runs[100] = [(0, {"status": "in_progress"}), (850, done("success"))]
        self.assertIn("1 dispatch", run(w, self.clock, cfg()))
        self.assertEqual(len(w.dispatched), 1)
        self.assertLessEqual(self.clock.t, 900 + 120)

    def test_follows_active_run_instead_of_dispatching(self):
        w = World(self.clock, {0: NO_KMOD, 500: FULL},
                  active={"in_progress": [{"id": 7, "html_url": "u7",
                                           "created_at": "2026-10-11T00:00:00Z"}]})
        w.runs[7] = [(0, {"status": "in_progress"}), (450, done("success"))]
        run(w, self.clock, cfg())
        self.assertEqual(w.dispatched, [])

    def test_adopted_success_without_package_dispatches_fresh(self):
        w = World(self.clock, {0: NO_KMOD, 2000: FULL},
                  active={"in_progress": [{"id": 7, "html_url": "u7",
                                           "created_at": "2026-10-11T00:00:00Z"}]})
        w.runs[7] = [(0, done("success"))]
        w.on_dispatch = lambda rid: w.runs.__setitem__(
            rid, [(self.clock(), {"status": "in_progress"}), (1900, done("success"))])
        run(w, self.clock, cfg())
        self.assertEqual(len(w.dispatched), 1)

    def test_own_success_without_package_fails_after_grace(self):
        w = World(self.clock, {0: NO_KMOD})
        w.runs[100] = [(0, {"status": "in_progress"}), (300, done("success"))]
        with self.assertRaisesRegex(m.Fatal, "Fedora's current kernel-devel"):
            run(w, self.clock, cfg())
        # success seen at the 360s tick, grace 600s
        self.assertEqual(self.clock.t, 960)
        self.assertEqual(len(w.dispatched), 1)

    def test_grace_is_capped_by_deadline(self):
        w = World(self.clock, {0: NO_KMOD})
        w.runs[100] = [(0, {"status": "in_progress"}), (3500, done("success"))]
        with self.assertRaisesRegex(m.Fatal, "finished successfully|gave up"):
            run(w, self.clock, cfg())
        self.assertEqual(self.clock.t, 3600)

    def test_chroot_lag_failure_retries_once_more(self):
        w = World(self.clock, {0: NO_KMOD, 1500: FULL})
        w.runs[100] = [(0, done("failure"))]
        w.jobs[100] = [{"steps": [{"name": "Build kmod-yeetmouse", "conclusion": "success"},
                                  {"name": m.CHROOT_LAG_STEP, "conclusion": "failure"}]}]
        w.runs[101] = [(0, {"status": "in_progress"})]
        run(w, self.clock, cfg())
        self.assertEqual(len(w.dispatched), 2)
        self.assertGreaterEqual(w.dispatched[1][0] - w.dispatched[0][0], 600)

    def test_other_failure_is_fatal(self):
        w = World(self.clock, {0: NO_KMOD})
        w.runs[100] = [(0, done("failure"))]
        w.jobs[100] = [{"steps": [{"name": "Build kmod-yeetmouse", "conclusion": "failure"}]}]
        with self.assertRaisesRegex(m.Fatal, "Build kmod-yeetmouse"):
            run(w, self.clock, cfg())
        self.assertEqual(len(w.dispatched), 1)

    def test_cancelled_follows_replacement(self):
        w = World(self.clock, {0: NO_KMOD, 1000: FULL})
        w.runs[100] = [(0, done("cancelled"))]
        repl = {"id": 55, "html_url": "u55", "created_at": "2026-10-11T00:05:00Z"}

        def after_first(rid):
            w.active = {"queued": [repl]}
        w.on_dispatch = after_first
        w.runs[55] = [(0, {"status": "queued"})]
        run(w, self.clock, cfg())
        self.assertEqual(len(w.dispatched), 1)

    def test_dispatch_cap(self):
        w = World(self.clock, {0: NO_KMOD})
        w.on_dispatch = lambda rid: w.runs.__setitem__(rid, [(0, done("cancelled"))])
        with self.assertRaisesRegex(m.Fatal, "already dispatched 3"):
            run(w, self.clock, cfg())

    def test_bad_token_is_fatal(self):
        w = World(self.clock, {0: NO_KMOD}, dispatch_status=403)
        with self.assertRaisesRegex(m.Fatal, "HTTP 403"):
            run(w, self.clock, cfg())

    def test_deadline(self):
        w = World(self.clock, {0: NO_KMOD})
        w.runs[100] = [(0, {"status": "in_progress"})]
        with self.assertRaisesRegex(m.Fatal, "gave up after 3600s"):
            run(w, self.clock, cfg())
        self.assertEqual(self.clock.t, 3600)

    def test_transient_repo_errors_are_retried(self):
        w = World(self.clock, {0: FULL})
        w.repomd_fail_until = 250
        w.runs[100] = [(0, {"status": "in_progress"})]
        run(w, self.clock, cfg())
        self.assertGreaterEqual(self.clock.t, 250)
        self.assertEqual(w.dispatched, [])  # never dispatch on unreadable metadata

    def test_checksum_mismatch_is_transient(self):
        good = primary(FULL)

        def http(method, url, headers, body=None):
            if "repomd.xml" in url:
                return m.Response(200, repomd(b"other", "repodata/p.xml.gz"))
            return m.Response(200, good)
        with self.assertRaisesRegex(IOError, "checksum mismatch"):
            m.read_repo(cfg(), http, 0)

    def test_xz_primary(self):
        import lzma
        data = primary(FULL, lzma.compress)

        def http(method, url, headers, body=None):
            if "repomd.xml" in url:
                return m.Response(200, repomd(data, "repodata/p.xml.xz"))
            return m.Response(200, data)
        self.assertEqual(m.missing_packages(cfg(), m.read_repo(cfg(), http, 0)), [])

    def test_bad_kver(self):
        with self.assertRaises(m.Fatal):
            m.config_from_env("7.2.9")

    def test_config_from_env(self):
        c = m.config_from_env(KVER, {"POLL_SECS": "5", "YEETMOUSE_DISPATCH_TOKEN": "t"})
        self.assertEqual((c.fedora, c.arch, c.poll_secs, c.token), ("44", "x86_64", 5.0, "t"))
        self.assertEqual(c.repo_url, "https://download.copr.fedorainfracloud.org/results/"
                         "abirkel/yeetmouse/fedora-44-x86_64/")


if __name__ == "__main__":
    unittest.main()
