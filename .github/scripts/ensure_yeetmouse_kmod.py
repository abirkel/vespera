#!/usr/bin/env python3
"""Make sure COPR abirkel/yeetmouse has a yeetmouse kmod for KVER before the image build.

Usage: ensure_yeetmouse_kmod.py KVER     (e.g. 7.2.9-200.fc44.x86_64)

build_files/30-kmods.sh installs kmod-yeetmouse-KVER, yeetmouse-kmod-common and
yeetmouse from COPR and fails the build when they are missing. That failure costs a
~20 minute image build and only says "re-run later". This preflight runs first and,
when the packages are missing, asks abirkel/yeetmouse-rpm to build them:

  1. Read COPR's repository metadata (what dnf will see). All three packages are
     present -> exit 0 at once.
  2. Missing -> if a poll-kernel-bump.yml run is already queued or running, follow it.
     Otherwise dispatch one (needs YEETMOUSE_DISPATCH_TOKEN, Actions: write on
     abirkel/yeetmouse-rpm).
  3. Recheck the metadata every POLL_SECS until one absolute deadline (DEADLINE_SECS
     from the start). Exit 0 as soon as the packages appear.
  4. The followed run ends:
       success   -> if the run was one this script dispatched, allow GRACE_SECS for
                    COPR to publish the repo, capped at the deadline. Still missing
                    then means the poller had nothing to build for this kernel: it
                    only builds against Fedora's CURRENT kernel-devel, so a base on
                    an older or newer kernel cannot be built by triggering. Fail with
                    that explanation. An adopted run may have started before the
                    kernel reached Fedora or COPR, so after one of those succeeds
                    without the packages, dispatch a fresh run instead.
       failure   -> if the only failed step is the poller's own "COPR chroot has an
                    older kernel-devel" check, re-dispatch after RETRY_DELAY_SECS.
                    Any other failure is real: fail with the run URL.
       cancelled -> another dispatch replaced it while pending (the poller's
                    concurrency group keeps one pending run). Follow the
                    replacement, or dispatch again if none is active.
  5. Deadline reached -> fail.

At most MAX_DISPATCHES dispatches are made. Standard library only, so it runs on the
stock ubuntu runner.
"""
from __future__ import annotations

import gzip
import hashlib
import json
import lzma
import bz2
import os
import re
import shutil
import subprocess
import sys
import time
import urllib.error
import urllib.request
import xml.etree.ElementTree as ET
from dataclasses import dataclass, field

REPO_NS = "{http://linux.duke.edu/metadata/repo}"
COMMON_NS = "{http://linux.duke.edu/metadata/common}"

KMOD_COMMON = "yeetmouse-kmod-common"
USERSPACE = "yeetmouse"

# Step name in yeetmouse-rpm's poll-kernel-bump.yml that fails when COPR's chroot
# still has the previous kernel-devel. That is the one failure worth retrying.
CHROOT_LAG_STEP = "Confirm the build is for this kernel"

ACTIVE_STATUSES = ("queued", "in_progress", "waiting", "pending", "requested")

KVER_RE = re.compile(r"^[0-9]+\.[0-9]+\.[0-9]+-[0-9a-z.]+\.fc([0-9]+)\.([a-z0-9_]+)$")


class Fatal(Exception):
    """Stop now with this message. Not retried."""


@dataclass
class Config:
    kver: str
    fedora: str
    arch: str
    copr_base: str = "https://download.copr.fedorainfracloud.org/results/abirkel/yeetmouse"
    gh_api: str = "https://api.github.com"
    gh_repo: str = "abirkel/yeetmouse-rpm"
    workflow: str = "poll-kernel-bump.yml"
    ref: str = "main"
    token: str = ""
    deadline_secs: float = 3600
    poll_secs: float = 120
    grace_secs: float = 600
    retry_delay_secs: float = 600
    max_dispatches: int = 3

    @property
    def repo_url(self) -> str:
        return f"{self.copr_base}/fedora-{self.fedora}-{self.arch}/"


def config_from_env(kver: str, env=os.environ) -> Config:
    m = KVER_RE.match(kver)
    if not m:
        raise Fatal(f"KVER {kver!r} is not VERSION-RELEASE.fcNN.ARCH")

    def num(name, default):
        raw = env.get(name)
        return float(raw) if raw else default

    return Config(
        kver=kver,
        fedora=m.group(1),
        arch=m.group(2),
        copr_base=env.get("COPR_BASE", Config.copr_base),
        gh_api=env.get("GH_API", Config.gh_api),
        gh_repo=env.get("YEETMOUSE_REPO", Config.gh_repo),
        workflow=env.get("YEETMOUSE_WORKFLOW", Config.workflow),
        ref=env.get("YEETMOUSE_REF", Config.ref),
        token=env.get("YEETMOUSE_DISPATCH_TOKEN", ""),
        deadline_secs=num("DEADLINE_SECS", Config.deadline_secs),
        poll_secs=num("POLL_SECS", Config.poll_secs),
        grace_secs=num("GRACE_SECS", Config.grace_secs),
        retry_delay_secs=num("RETRY_DELAY_SECS", Config.retry_delay_secs),
        max_dispatches=int(num("MAX_DISPATCHES", Config.max_dispatches)),
    )


# ---------------------------------------------------------------------------
# HTTP. One function so tests can replace it.
# ---------------------------------------------------------------------------
@dataclass
class Response:
    status: int
    body: bytes


def urllib_http(method: str, url: str, headers: dict, body: bytes | None = None) -> Response:
    req = urllib.request.Request(url, data=body, method=method, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            return Response(r.status, r.read())
    except urllib.error.HTTPError as e:
        return Response(e.code, e.read())


# ---------------------------------------------------------------------------
# COPR repository metadata
# ---------------------------------------------------------------------------
def decompress(name: str, data: bytes) -> bytes:
    if name.endswith(".gz"):
        return gzip.decompress(data)
    if name.endswith(".xz"):
        return lzma.decompress(data)
    if name.endswith(".bz2"):
        return bz2.decompress(data)
    if name.endswith(".zst"):
        try:
            from compression import zstd  # Python 3.14+
            return zstd.decompress(data)
        except ImportError:
            if not shutil.which("zstd"):
                raise Fatal(f"{name} is zstd-compressed and no zstd decoder is available")
            return subprocess.run(
                ["zstd", "-dc"], input=data, capture_output=True, check=True
            ).stdout
    if name.endswith(".xml"):
        return data
    raise Fatal(f"unknown compression for repo metadata file {name}")


@dataclass
class RepoState:
    revision: str
    # name -> list of (arch, "epoch:version-release")
    packages: dict = field(default_factory=dict)

    def evrs(self, name: str, archs: tuple) -> set:
        return {evr for a, evr in self.packages.get(name, []) if a in archs}


def read_repo(cfg: Config, http, now: float) -> RepoState:
    """Fetch repomd.xml, then the primary metadata it names, and verify its checksum.

    repomd.xml is fetched with no-cache headers and a throwaway query string so a CDN
    cannot hand back a copy from before COPR published. The primary file name is a
    content hash, so it cannot be stale once repomd is current.
    """
    headers = {"Cache-Control": "no-cache", "Pragma": "no-cache"}
    r = http("GET", f"{cfg.repo_url}repodata/repomd.xml?cb={int(now)}", headers)
    if r.status != 200:
        raise IOError(f"repomd.xml: HTTP {r.status}")
    root = ET.fromstring(r.body)
    revision = (root.findtext(f"{REPO_NS}revision") or "").strip()
    primary = next(
        (d for d in root.findall(f"{REPO_NS}data") if d.get("type") == "primary"), None
    )
    if primary is None:
        raise IOError("repomd.xml has no primary data entry")
    href = primary.find(f"{REPO_NS}location").get("href")
    checksum = primary.find(f"{REPO_NS}checksum")
    r = http("GET", cfg.repo_url + href, headers)
    if r.status != 200:
        raise IOError(f"{href}: HTTP {r.status}")
    if checksum is not None and checksum.get("type") in hashlib.algorithms_available:
        got = hashlib.new(checksum.get("type"), r.body).hexdigest()
        if got != checksum.text.strip():
            raise IOError(f"{href}: checksum mismatch (CDN mid-update?)")
    xml = decompress(href, r.body)

    state = RepoState(revision=revision)
    for pkg in ET.fromstring(xml).iter(f"{COMMON_NS}package"):
        name = pkg.findtext(f"{COMMON_NS}name")
        arch = pkg.findtext(f"{COMMON_NS}arch")
        v = pkg.find(f"{COMMON_NS}version")
        evr = f"{v.get('epoch', '0')}:{v.get('ver')}-{v.get('rel')}"
        state.packages.setdefault(name, []).append((arch, evr))
    return state


def missing_packages(cfg: Config, state: RepoState) -> list:
    """What 30-kmods.sh would fail to install, or [] when everything is there."""
    kmod = f"kmod-yeetmouse-{cfg.kver}"
    kmod_evrs = state.evrs(kmod, (cfg.arch,))
    missing = []
    if not kmod_evrs:
        missing.append(kmod)
    else:
        # kmodtool's per-kernel package requires the kmod-common built with it, so
        # the matching version-release must be published too.
        common = state.evrs(KMOD_COMMON, ("noarch", cfg.arch))
        if not kmod_evrs & common:
            missing.append(f"{KMOD_COMMON} at {', '.join(sorted(kmod_evrs))}")
    if not state.evrs(USERSPACE, (cfg.arch,)):
        missing.append(USERSPACE)
    return missing


# ---------------------------------------------------------------------------
# GitHub Actions on abirkel/yeetmouse-rpm
# ---------------------------------------------------------------------------
class GitHub:
    def __init__(self, cfg: Config, http):
        self.cfg = cfg
        self.http = http

    def _headers(self) -> dict:
        h = {
            "Accept": "application/vnd.github+json",
            "X-GitHub-Api-Version": "2022-11-28",
            "User-Agent": "vespera-ensure-yeetmouse-kmod",
        }
        if self.cfg.token:
            h["Authorization"] = f"Bearer {self.cfg.token}"
        return h

    def _get(self, path: str) -> dict:
        r = self.http("GET", f"{self.cfg.gh_api}/repos/{self.cfg.gh_repo}{path}", self._headers())
        if r.status != 200:
            raise IOError(f"GET {path}: HTTP {r.status}")
        return json.loads(r.body)

    def active_run(self):
        """The newest queued/running poll-kernel-bump run, or None."""
        for status in ACTIVE_STATUSES:
            runs = self._get(
                f"/actions/workflows/{self.cfg.workflow}/runs?status={status}&per_page=5"
            ).get("workflow_runs", [])
            if runs:
                return max(runs, key=lambda r: r["created_at"])
        return None

    def dispatch(self) -> int:
        body = json.dumps({"ref": self.cfg.ref, "return_run_details": True}).encode()
        h = dict(self._headers(), **{"Content-Type": "application/json"})
        r = self.http(
            "POST",
            f"{self.cfg.gh_api}/repos/{self.cfg.gh_repo}/actions/workflows/"
            f"{self.cfg.workflow}/dispatches",
            h,
            body,
        )
        if r.status in (401, 403, 404, 422):
            # Not transient: a bad, expired or under-scoped token, or a renamed workflow.
            raise Fatal(
                f"dispatching {self.cfg.workflow} on {self.cfg.gh_repo} was refused "
                f"(HTTP {r.status}). Check that YEETMOUSE_DISPATCH_TOKEN is valid and has "
                "Actions: read and write on that repository."
            )
        if r.status != 200:
            raise IOError(f"dispatch: HTTP {r.status}")
        run_id = json.loads(r.body).get("workflow_run_id")
        if not run_id:
            raise Fatal("dispatch succeeded but GitHub returned no workflow_run_id")
        return int(run_id)

    def run(self, run_id: int) -> dict:
        return self._get(f"/actions/runs/{run_id}")

    def failed_steps(self, run_id: int) -> list:
        jobs = self._get(f"/actions/runs/{run_id}/jobs").get("jobs", [])
        return [
            s["name"]
            for j in jobs
            for s in j.get("steps", [])
            if s.get("conclusion") == "failure"
        ]


# ---------------------------------------------------------------------------
# The wait loop
# ---------------------------------------------------------------------------
def log(msg: str) -> None:
    print(msg, flush=True)


def ensure(cfg: Config, http=urllib_http, clock=time.monotonic, sleep=time.sleep,
           wall=time.time) -> str:
    """Return a one-line summary on success, raise Fatal on failure."""
    gh = GitHub(cfg, http)
    start = clock()
    deadline = start + cfg.deadline_secs
    tracked = None          # run id being followed
    tracked_url = ""
    tracked_ours = False    # dispatched by this invocation, not adopted
    may_adopt = True        # follow an already-active run instead of dispatching
    dispatches = 0
    next_dispatch_at = start
    grace_until = None      # set when a followed run succeeded
    last_missing = ["(not checked yet)"]

    def elapsed() -> str:
        return f"{int(clock() - start)}s"

    while True:
        now = clock()
        repo_ok = False
        try:
            state = read_repo(cfg, http, wall())
            repo_ok = True
            last_missing = missing_packages(cfg, state)
            if not last_missing:
                return (f"yeetmouse packages for {cfg.kver} are in COPR "
                        f"(repo revision {state.revision}, after {elapsed()}, "
                        f"{dispatches} dispatch(es))")
            log(f"[{elapsed()}] COPR revision {state.revision}: missing "
                f"{', '.join(last_missing)}")
        except IOError as e:
            log(f"[{elapsed()}] could not read COPR metadata, will retry: {e}")

        # Judge "still missing" only on metadata actually read this tick.
        if repo_ok and grace_until is not None and now >= grace_until:
            raise Fatal(
                f"{tracked_url} finished successfully but COPR still lacks "
                f"{', '.join(last_missing)}. poll-kernel-bump builds only against "
                "Fedora's current kernel-devel, so this base kernel is not the one it "
                f"builds (an older or not-yet-current kernel). Triggering cannot build "
                f"{cfg.kver}; move the base to Fedora's current kernel or build the kmod "
                "by hand."
            )
        if now >= deadline:
            raise Fatal(
                f"gave up after {elapsed()}: COPR still lacks {', '.join(last_missing)}"
                + (f" (last run followed: {tracked_url})" if tracked_url else "")
            )

        try:
            # Never request a build on a guess: only when the metadata was read and
            # something is missing.
            if (repo_ok and tracked is None and grace_until is None
                    and now >= next_dispatch_at):
                active = gh.active_run() if may_adopt else None
                if active:
                    tracked, tracked_url = active["id"], active["html_url"]
                    tracked_ours = False
                    log(f"[{elapsed()}] following already-active run {tracked_url}")
                elif not cfg.token:
                    raise Fatal(
                        f"COPR lacks {', '.join(last_missing)} and no "
                        "YEETMOUSE_DISPATCH_TOKEN is set, so a kmod build cannot be "
                        f"requested. Run {cfg.workflow} in {cfg.gh_repo} by hand, or add "
                        "the secret (fine-grained token, that repository only, "
                        "Actions: read and write)."
                    )
                elif dispatches >= cfg.max_dispatches:
                    raise Fatal(
                        f"already dispatched {dispatches} time(s) and COPR still lacks "
                        f"{', '.join(last_missing)}"
                    )
                else:
                    tracked = gh.dispatch()
                    tracked_ours = True
                    dispatches += 1
                    tracked_url = (f"https://github.com/{cfg.gh_repo}/actions/runs/"
                                   f"{tracked}")
                    log(f"[{elapsed()}] dispatched {cfg.workflow}: {tracked_url}")

            elif tracked is not None:
                run = gh.run(tracked)
                if run.get("status") == "completed":
                    conclusion = run.get("conclusion")
                    log(f"[{elapsed()}] {tracked_url} completed: {conclusion}")
                    if conclusion == "success" and not tracked_ours:
                        # An adopted run may have started before Fedora or COPR saw
                        # this kernel. Only a run started after we found the gap can
                        # prove the kernel is unbuildable, so dispatch our own.
                        may_adopt = False
                        next_dispatch_at = clock()
                    elif conclusion == "success":
                        grace_until = min(clock() + cfg.grace_secs, deadline)
                    elif conclusion == "cancelled":
                        # Replaced while pending. Pick up the replacement next tick.
                        next_dispatch_at = clock()
                    elif conclusion == "failure":
                        steps = gh.failed_steps(tracked)
                        if steps == [CHROOT_LAG_STEP]:
                            log(f"[{elapsed()}] COPR's chroot had an older kernel-devel; "
                                f"retrying in {int(cfg.retry_delay_secs)}s")
                            next_dispatch_at = clock() + cfg.retry_delay_secs
                        else:
                            raise Fatal(
                                f"{tracked_url} failed in step(s) "
                                f"{', '.join(steps) or '(unknown)'}. That is not the "
                                "known chroot-lag case, so it is not retried."
                            )
                    else:
                        raise Fatal(f"{tracked_url} ended {conclusion}; not retried")
                    tracked = None
        except IOError as e:
            log(f"[{elapsed()}] GitHub API error, will retry: {e}")

        now = clock()
        wake = min(now + cfg.poll_secs, deadline)
        if grace_until is not None:
            wake = min(wake, grace_until)
        sleep(max(0.0, wake - now))


def main(argv) -> int:
    if len(argv) != 2:
        print(__doc__, file=sys.stderr)
        return 2
    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    try:
        cfg = config_from_env(argv[1])
        msg = ensure(cfg)
        log(msg)
        rc = 0
    except Fatal as e:
        msg = str(e)
        print(f"::error title=yeetmouse kmod unavailable::{msg}", flush=True)
        rc = 1
    if summary:
        with open(summary, "a", encoding="utf-8") as f:
            f.write(f"### yeetmouse kmod preflight\n\n{'OK' if rc == 0 else 'FAILED'}: "
                    f"{msg}\n")
    return rc


if __name__ == "__main__":
    sys.exit(main(sys.argv))
