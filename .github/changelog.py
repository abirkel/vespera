#!/usr/bin/env python3
"""Generate release notes for a published vespera image.

PROVENANCE: structure, the epoch/.fcNN normalisation, numeric tag ordering, the
previous-tag search and the commit table all follow ublue's changelog scripts
(ublue-os/bazzite .github/workflows/changelog.py and the near-identical
ublue-os/aurora .github/changelogs.py). The headline package list is Aurora's.

TWO DELIBERATE DEVIATIONS from ublue, both measured against their own published
release notes for bazzite 44.20260831 -> 44.20260902 (56 real package changes):

1. DATA SOURCE. They attach a full syft SBOM and read three fields out of it. On
   bazzite:stable that SBOM is 198,515,288 bytes, because syft catalogues and hashes
   every file, and producing it costs a `podman export` of the entire rootfs plus a
   tar extraction. This reads the ~200 KB package manifest the build already has to
   compute for its no-op gate.

2. GROUPING. They collapse the package list with "one package per new version": any
   package whose current OR previous version string was already emitted is dropped.
   That folds subpackages together, but it keys on a coincidence rather than a fact,
   and it also seeds the suppression set from packages that did NOT change. Measured
   consequences on that release: 27 rows shown out of 56 real changes, and five source
   packages missing from the notes entirely -
     fcitx5-qt        5.1.14-1 -> 5.1.14-3  (hidden by UNCHANGED fcitx5-configtool)
     qt6              6.11.1-1 -> 6.11.2-1  (hidden by UNCHANGED qt6-filesystem)
     kdeplasma-addons 6.7.4-1  -> 6.7.4-2   (hidden by unrelated breeze-cursor-theme)
     kvmfr, openrazer  newly added          (hidden by kmod-* of a different source)
   Grouping on %{SOURCERPM} instead is exact. It must include the source VERSION, not
   just the name: bazzite ships two different source builds both named `kernel`
   (Fedora's kernel-7.1.12-200 and OGC's kernel-7.2.1-ogc4.1), and keying on the name
   alone merges them and loses a real kernel-tools update. With name+version the same
   release yields 33 rows, loses nothing ublue showed, and adds the five above.
"""

from collections import defaultdict
import argparse
import json
import os
import re
import subprocess
import sys
import tempfile
import time

REGISTRY = os.environ.get("IMAGE_REGISTRY", "ghcr.io/abirkel")
IMAGE = os.environ.get("IMAGE_NAME", "vespera")
REPO_URL = os.environ.get("REPO_URL", "https://github.com/abirkel/vespera")
ARTIFACT_TYPE = "application/vnd.vespera.packages.v1+json"

RETRIES = 3
RETRY_WAIT = 5

# Strip the noise that makes every row wider without saying anything: the Fedora release
# suffix is the same for every package, and a zero epoch is an implementation detail.
FEDORA_PATTERN = re.compile(r"\.fc\d\d")
EPOCH_PATTERN = re.compile(r"^\d+:")
TAG_NUM_PATTERN = re.compile(r"(\d+)")
PKGREL_PATTERN = re.compile(r"\{pkgrel:[^}]+\}")
SRPM_PATTERN = re.compile(r"-[^-]+-[^-]+$")

# Aurora's headline set. These are shown with an explicit before/after at the top and
# excluded from the table below it, so the interesting versions are not buried in a
# hundred rows of dependencies.
HEADLINE = [
    ("Kernel", "kernel-core"),
    ("KDE", "plasma-desktop"),
    ("Mesa", "mesa-filesystem"),
    ("Nvidia", "nvidia-driver"),
    ("Podman", "podman"),
    ("Bootc", "bootc"),
    ("Flatpak", "flatpak"),
    ("OSTree", "ostree"),
    ("RPM-OSTree", "rpm-ostree"),
]
HEADLINE_PKGS = {pkg for _, pkg in HEADLINE}

PATTERN_ADD = "\n| ✨ | {name} | | {version} |"
PATTERN_CHANGE = "\n| 🔄 | {name} | {prev} | {new} |"
PATTERN_REMOVE = "\n| ❌ | {name} | {version} | |"
CHANGES_FORMAT = (
    "### Packages\n"
    "Grouped by source package, so one row is one update even when it ships several "
    "subpackages.\n\n"
    "| | Source package | Previous | New |\n| --- | --- | --- | --- |{changes}\n\n"
)
COMMITS_FORMAT = "### Commits\n| Hash | Subject | Author |\n| --- | --- | --- |{commits}\n\n"
COMMIT_FORMAT = "\n| **[{short}](" + "{repo}" + "/commit/{hash})** | {subject} | {author} |"

CHANGELOG_TITLE = "{tag}"
CHANGELOG_FORMAT = """\
Automatically generated changelog for `{curr}`.

Changes since `{prev}`.

### Headline packages
| Name | Version |
| --- | --- |
{headline}

{changes}
### How to rebase
```bash
# Track this stream and pick up future builds automatically:
sudo bootc switch {imageref}:latest
# Or pin exactly this build:
sudo bootc switch {imageref}:{curr}
```
"""


def run(cmd, **kw):
    return subprocess.run(cmd, check=True, stdout=subprocess.PIPE, **kw).stdout


def get_manifest(tag: str):
    """skopeo inspect with retries; the registry is occasionally flaky."""
    ref = f"docker://{REGISTRY}/{IMAGE}:{tag}"
    for i in range(RETRIES):
        try:
            return json.loads(run(["skopeo", "inspect", ref]))
        except subprocess.CalledProcessError:
            if i == RETRIES - 1:
                raise
            print(f"failed to inspect {tag}, retrying in {RETRY_WAIT}s ({i+1}/{RETRIES})")
            time.sleep(RETRY_WAIT)


def tag_sort_key(tag: str):
    """Order tags numerically so .10 sorts after .2."""
    return [int(p) if p.isdigit() else p for p in re.split(TAG_NUM_PATTERN, tag)]


def get_prev_tag(manifest, curr: str, fedora_major: str):
    """Newest published dated tag older than curr.

    Only `<major>.<date>.<n>` tags qualify. `latest` and the bare major move, and a
    moving tag cannot anchor a diff.
    """
    pattern = re.compile(rf"^{re.escape(fedora_major)}\.\d{{8}}\.\d+$")
    curr_key = tag_sort_key(curr)
    tags = sorted(
        (t for t in manifest.get("RepoTags", []) if pattern.match(t)
         and tag_sort_key(t) < curr_key),
        key=tag_sort_key,
    )
    return tags[-1] if tags else None


def get_packages(tag: str):
    """Pull the package manifest attached to a tag as an OCI referrer."""
    digest = get_manifest(tag)["Digest"]
    ref = f"{REGISTRY}/{IMAGE}@{digest}"
    discovered = json.loads(run(["oras", "discover", "--format", "json", ref]))
    match = next(
        (r for r in discovered.get("referrers", [])
         if r.get("artifactType") == ARTIFACT_TYPE),
        None,
    )
    if match is None:
        raise RuntimeError(f"no {ARTIFACT_TYPE} referrer on {tag}")
    with tempfile.TemporaryDirectory() as tmp:
        run(["oras", "pull", f"{REGISTRY}/{IMAGE}@{match['digest']}"], cwd=tmp)
        for name in os.listdir(tmp):
            if name.endswith(".json"):
                with open(os.path.join(tmp, name)) as f:
                    return json.load(f)
    raise RuntimeError(f"referrer on {tag} contained no json payload")


def parse_packages(doc):
    """name -> version, preferring the epoch-qualified form. Matches ublue's helper."""
    out = {}
    for art in doc.get("artifacts", []):
        if art.get("type") != "rpm":
            continue
        name, ver = art.get("name"), art.get("version")
        if not name or not ver:
            continue
        if name not in out or (":" in ver and ":" not in out[name]):
            out[name] = ver
    return out


def source_of(doc):
    """name -> source package NAME-VERSION-RELEASE, with .src.rpm removed."""
    out = {}
    for art in doc.get("artifacts", []):
        if art.get("type") != "rpm":
            continue
        srpm = (art.get("metadata") or {}).get("sourceRpm") or ""
        if srpm.endswith(".src.rpm"):
            srpm = srpm[: -len(".src.rpm")]
        if art.get("name"):
            out[art["name"]] = srpm
    return out


def normalise(versions: dict):
    return {
        n: FEDORA_PATTERN.sub("", EPOCH_PATTERN.sub("", v)) for n, v in versions.items()
    }


def srpm_name(srpm: str, fallback: str):
    """Drop the source package's version-release, keeping only its name."""
    return SRPM_PATTERN.sub("", FEDORA_PATTERN.sub("", srpm)) or fallback


def calculate_changes(prev, curr, prev_src, curr_src):
    """Group changed binary packages by source build and render one row each."""
    groups = defaultdict(list)
    for name in sorted(set(prev) | set(curr)):
        if prev.get(name) == curr.get(name):
            continue
        if name in HEADLINE_PKGS:
            continue  # already shown above, with its own before/after
        srpm = curr_src.get(name) or prev_src.get(name) or ""
        # The version belongs in the key: two different source builds can share a name
        # (Fedora's `kernel` and a vendor `kernel`), and merging them hides real updates.
        key = (srpm_name(srpm, name), prev.get(name), curr.get(name))
        groups[key].append(name)

    added, changed, removed = [], [], []
    for (name, pv, cv), members in groups.items():
        entry = (name, pv, cv, sorted(members))
        if pv is None:
            added.append(entry)
        elif cv is None:
            removed.append(entry)
        else:
            changed.append(entry)

    out = ""
    for name, _, cv, _ in sorted(added):
        out += PATTERN_ADD.format(name=name, version=cv)
    for name, pv, cv, _ in sorted(changed):
        out += PATTERN_CHANGE.format(name=name, prev=pv, new=cv)
    for name, pv, _, _ in sorted(removed):
        out += PATTERN_REMOVE.format(name=name, version=pv)
    return out


def get_commits(prev_manifest, curr_manifest, workdir: str):
    """Commit table between the two images' recorded revisions."""
    try:
        start = prev_manifest["Labels"]["org.opencontainers.image.revision"]
        finish = curr_manifest["Labels"]["org.opencontainers.image.revision"]
        if not start or not finish or start == finish:
            return ""
        log = run(
            ["git", "-C", workdir, "log", "--pretty=format:%H|%h|%an|%s",
             f"{start}..{finish}"]
        ).decode()
    except Exception as e:  # a shallow clone or a missing label must not fail the release
        print(f"skipping commit table: {e}")
        return ""

    out = ""
    for line in log.split("\n"):
        parts = line.split("|")
        if len(parts) < 4:
            continue
        full, short, author, subject = parts[0], parts[1], parts[2], "|".join(parts[3:])
        if subject.lower().startswith("merge"):
            continue
        out += (
            COMMIT_FORMAT.replace("{short}", short)
            .replace("{repo}", REPO_URL)
            .replace("{hash}", full)
            .replace("{subject}", subject.replace("|", "\\|"))
            .replace("{author}", author)
        )
    return COMMITS_FORMAT.format(commits=out) if out else ""


def build_headline(prev, curr):
    rows = []
    for label, pkg in HEADLINE:
        cv, pv = curr.get(pkg), prev.get(pkg)
        if cv is None and pv is None:
            value = "N/A"
        elif pv is None or pv == cv:
            value = cv or "N/A"
        else:
            value = f"{pv} ➡️ {cv}"
        rows.append(f"| **{label}** | {value} |")
    return "\n".join(rows)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("version", help="version tag just published, e.g. 44.20260903.1")
    ap.add_argument("output", help="file to write TITLE/TAG to")
    ap.add_argument("changelog", help="file to write the release body to")
    ap.add_argument("--workdir", default=".", help="git checkout for the commit table")
    args = ap.parse_args()

    curr_tag = args.version
    fedora_major = curr_tag.split(".")[0]

    curr_manifest = get_manifest(curr_tag)
    prev_tag = get_prev_tag(curr_manifest, curr_tag, fedora_major)
    print(f"current: {curr_tag}\nprevious: {prev_tag}")

    curr_doc = get_packages(curr_tag)
    curr = normalise(parse_packages(curr_doc))
    curr_src = source_of(curr_doc)

    if prev_tag is None:
        # First dated build, or the first one carrying a manifest. Publish the headline
        # versions and say so, rather than inventing a diff against nothing.
        body = (
            f"Automatically generated changelog for `{curr_tag}`.\n\n"
            "First published build with a package manifest attached, so there is no "
            "previous image to compare against. Package changes will be listed from the "
            "next build onward.\n\n"
            "### Headline packages\n| Name | Version |\n| --- | --- |\n"
            + build_headline({}, curr)
            + "\n"
        )
    else:
        prev_manifest = get_manifest(prev_tag)
        prev_doc = get_packages(prev_tag)
        prev = normalise(parse_packages(prev_doc))
        prev_src = source_of(prev_doc)

        rows = calculate_changes(prev, curr, prev_src, curr_src)
        changes = get_commits(prev_manifest, curr_manifest, args.workdir)
        if rows:
            changes += CHANGES_FORMAT.format(changes=rows)
        elif any(prev.get(n) != curr.get(n) for n in set(prev) | set(curr)):
            # Something moved, but every changed package is in the headline table above,
            # so an empty table here would read as "nothing changed" and contradict it.
            changes += (
                "### Packages\nAll package changes are in the headline table above.\n\n"
            )
        else:
            changes += (
                "### Packages\nNo package changes; this build differs only in "
                "configuration.\n\n"
            )
        body = (
            CHANGELOG_FORMAT.replace("{headline}", build_headline(prev, curr))
            .replace("{changes}", changes)
            .replace("{imageref}", f"{REGISTRY}/{IMAGE}")
            .replace("{prev}", prev_tag)
            .replace("{curr}", curr_tag)
        )
        body = PKGREL_PATTERN.sub("N/A", body)

    title = CHANGELOG_TITLE.format(tag=curr_tag)
    with open(args.changelog, "w") as f:
        f.write(body)
    with open(args.output, "w") as f:
        f.write(f'TITLE="{title}"\nTAG={curr_tag}\n')
    print(f"\n--- {title} ---\n{body}")


if __name__ == "__main__":
    sys.exit(main())
