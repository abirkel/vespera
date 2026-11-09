#!/usr/bin/env python3
"""Print the retained uBlue akmods tag that matches a base image.

Usage: skopeo inspect --config docker://BASE | resolve_akmods_candidate.py FLAVOR

uBlue retains akmods images as <flavor>-<fedora major>-<kernel EVR>, for example
main-45-7.2.15-300.fc45. Both the Fedora major and the kernel come from the base image,
so a base that crosses to a new Fedora release needs no hand edit.

The Fedora major is read from two labels that must agree, so a changed label format or a
mislabelled image fails here and not as a confusing missing-tag error later:

  org.opencontainers.image.version   44.20261107.1            -> 44
  ostree.linux                       7.2.15-200.fc44.x86_64   -> 44, EVR 7.2.15-200.fc44

Prints the candidate tag on stdout. Any problem prints a message to stderr and exits 1.
Used by .github/workflows/build.yml and check-kernel-sync.yml.
"""
import json
import re
import sys

VERSION_RE = re.compile(r"^(\d+)\.")
KERNEL_RE = re.compile(r"^(?P<evr>.+\.fc(?P<major>\d+))\.(?P<arch>[A-Za-z0-9_]+)$")
FLAVOR_RE = re.compile(r"^[a-z][a-z0-9]*(?:-[a-z][a-z0-9]*)*$")


class ResolveError(Exception):
    pass


def resolve(flavor, config):
    """Return (fedora_major, kernel_evr, candidate_tag) for a `skopeo inspect --config` dict."""
    if not FLAVOR_RE.match(flavor):
        raise ResolveError(f"invalid akmods flavor {flavor!r}")
    inner = config.get("config") if isinstance(config, dict) else None
    labels = inner.get("Labels") if isinstance(inner, dict) else None
    if not isinstance(labels, dict):
        raise ResolveError("base image config has no Labels object")

    version = labels.get("org.opencontainers.image.version", "")
    if not isinstance(version, str):
        raise ResolveError(
            f"base org.opencontainers.image.version is not a string: {version!r}")
    m = VERSION_RE.match(version)
    if not m:
        raise ResolveError(
            f"base org.opencontainers.image.version {version!r} does not start with a "
            "Fedora major (expected NN.DATE...)")
    version_major = m.group(1)

    kernel = labels.get("ostree.linux", "")
    if not isinstance(kernel, str):
        raise ResolveError(f"base ostree.linux is not a string: {kernel!r}")
    k = KERNEL_RE.match(kernel)
    if not k:
        raise ResolveError(
            f"base ostree.linux {kernel!r} is not VERSION-RELEASE.fcNN.ARCH")
    kernel_major = k.group("major")

    if version_major != kernel_major:
        raise ResolveError(
            f"base labels disagree on the Fedora release: version {version!r} says "
            f"{version_major}, kernel {kernel!r} says {kernel_major}")

    evr = k.group("evr")
    return version_major, evr, f"{flavor}-{version_major}-{evr}"


def main(argv):
    if len(argv) != 2:
        print("usage: resolve_akmods_candidate.py FLAVOR < config.json", file=sys.stderr)
        return 2
    try:
        config = json.load(sys.stdin)
    except json.JSONDecodeError as exc:
        print(f"base image config is not valid JSON: {exc}", file=sys.stderr)
        return 1
    try:
        _, _, tag = resolve(argv[1], config)
    except ResolveError as exc:
        print(str(exc), file=sys.stderr)
        return 1
    print(tag)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
