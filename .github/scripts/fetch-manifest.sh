#!/usr/bin/env bash
# fetch-manifest.sh <registry>/<image> <tag> [artifact-type]
#
# Prints the local path to the package-manifest JSON attached (via oras) to
# the given tag's image, or nothing (exit 0, no output) if it cannot be
# found after retrying. Callers must check for empty output themselves —
# this script does not fail the build on a missing manifest, since "no
# manifest yet" is a legitimate state (first-ever publish, or a registry
# propagation blip) that callers handle differently depending on context.
#
# EXTRACTED from promote.yml's inline fetch_manifest_json(), which needed
# this same logic duplicated the moment build.yml also needed to compare
# testing against latest (for the fast-path headline check dispatched
# BEFORE promote.yml even runs). One implementation, called from both
# workflows, rather than two copies drifting apart.
set -euo pipefail

IMAGE_REF="$1"
TAG="$2"
ARTIFACT_TYPE="${3:-application/vnd.vespera.packages.v1+json}"

digest=""
for attempt in 1 2 3 4; do
  digest="$(skopeo inspect "docker://${IMAGE_REF}:${TAG}" 2>/dev/null \
    | jq -r '.Digest // empty')"
  [[ -n "${digest}" ]] && break
  echo "::notice::${TAG}: digest not found yet (attempt ${attempt}/4), retrying in 10s" >&2
  sleep 10
done
[[ -n "${digest}" ]] || exit 0

artifact_digest=""
for attempt in 1 2 3 4; do
  artifact_digest="$(
    oras discover --format json "${IMAGE_REF}@${digest}" \
      | jq -r --arg t "${ARTIFACT_TYPE}" \
          '(.referrers // .manifests // [])[]? | select(.artifactType == $t) | .digest'
  )"
  artifact_digest="$(printf '%s\n' "${artifact_digest}" | head -1)"
  [[ -n "${artifact_digest}" ]] && break
  MSG="${TAG}: manifest referrer not found yet (attempt ${attempt}/4), retrying in 10s"
  echo "::notice::${MSG}" >&2
  sleep 10
done
[[ -n "${artifact_digest}" ]] || exit 0

workdir="$(mktemp -d)"
# --allow-path-traversal: defensive-in-depth against a referrer whose OWN internal
# file metadata records an absolute source path (which is exactly what an
# oras-attach given an absolute path bakes in — see the Attach package manifest
# step in promote.yml, now fixed to always attach a relative path so this should
# never recur going forward). Safe here because -o already pins the actual
# extraction target to our own controlled mktemp dir regardless of what the
# artifact's internal metadata claims.
oras pull --allow-path-traversal "${IMAGE_REF}@${artifact_digest}" -o "${workdir}" >/dev/null
find "${workdir}" -name '*.json' -print -quit
