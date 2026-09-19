#!/usr/bin/env python3
"""Decide whether a :testing publish is worth promoting to :latest.

Compares two package-manifest JSON files (the same OCI-referrer manifests
build.yml attaches on every publish and changelog.py already reads) and
prints promote=true/false plus a human-readable reason, in GitHub Actions
$GITHUB_OUTPUT format.

SINGLE SOURCE OF TRUTH for the headline package set: imported from
changelog.py rather than duplicated a third time. There were previously
THREE copies of this same list (promote.yml's inline Python, build.yml
had none, changelog.py) — this script and changelog.py now share the one
definition in changelog.py.

USED FROM TWO PLACES, on purpose:
  - build.yml, right after a real publish, to decide whether to even
    dispatch promote.yml at all (the "fast path" — most publishes are NOT
    headline-worthy, and skipping the dispatch entirely means promote.yml
    no longer runs-and-usually-says-no on every single testing publish).
  - promote.yml's own schedule (weekly floor) and workflow_dispatch
    triggers, which have no upstream build.yml decision to rely on and
    must make this call themselves (the "slow path" / safety net — catches
    a quiet week where build.yml's own dispatch never fired, or a manual
    check on demand).

Base image identity is intentionally NOT checked here — see promote.yml's
history. It moves almost daily on its own and would otherwise promote
almost every day, defeating the point of a weekly-by-default floor.
"""
import json
import sys
from pathlib import Path

# changelog.py lives next to this script's parent directory (.github/), not
# next to this script itself (.github/scripts/).
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from changelog import HEADLINE_PKGS  # noqa: E402


def versions(doc):
    out = {}
    for art in doc.get("artifacts", []):
        if art.get("type") == "rpm" and art.get("name"):
            out[art["name"]] = art.get("version")
    return out


def main():
    if len(sys.argv) != 3:
        print("usage: headline-check.py <testing-manifest.json> <latest-manifest.json>",
              file=sys.stderr)
        return 2

    with open(sys.argv[1]) as f:
        testing = json.load(f)
    with open(sys.argv[2]) as f:
        latest = json.load(f)

    tv, lv = versions(testing), versions(latest)
    changed_headline = sorted(n for n in HEADLINE_PKGS if tv.get(n) != lv.get(n))

    if changed_headline:
        print("promote=true")
        print("reason=headline packages changed: " + ", ".join(changed_headline))
    else:
        print("promote=false")
        print("reason=no headline package change since last promotion")
    return 0


if __name__ == "__main__":
    sys.exit(main())
