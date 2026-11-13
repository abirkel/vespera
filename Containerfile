# vespera — a custom KDE gaming + light-dev image on ublue's kinoite-main.
#
# Base is Fedora Kinoite + a Secure-Boot-signed matching kernel + negativo17 codecs.
# build_files/nvidia.sh adds nvidia-open and the full 32-bit driver stack, the same
# way ublue's retired kinoite-nvidia did. Discover survives here (unlike
# Bazzite/Aurora), though its rpm-ostree backend must be added back — see
# 10-packages-fedora.sh.
#
# Branding stays STOCK: /usr/lib/os-release, logos and PRETTY_NAME are untouched. The
# only metadata corrected is the image ref in image-info.json, so update tooling
# targets this registry rather than ublue's.
#
# Following Fedora automatically
# -----------------------------------------------------------------------------
# BASE_TAG is `latest`, not a pinned `44`. ublue publishes a numeric tag per release
# plus a rolling `latest`, and promotes `latest` to the next Fedora when they judge it
# ready (verified: `latest` and `44` are the same digest today). That delegates the "is
# F45 ready?" decision to the people rebuilding this base daily.
#
# Renovate still pins the digest, so builds are reproducible and each base change is a
# reviewable commit with CI attached — including the one where `latest` crosses 44 to
# 45. If that breaks the build the PR stays red, nothing is pushed, and the machine
# keeps running the last good image.
#
# Nothing else hardcodes the version; the build reads it with `rpm -E %fedora`
# (lib/common.sh). Do NOT use ublue's `stable` tag — abandoned, still Fedora 37.
#
# Renovate expands ARG defaults used in FROM and rewrites the ARG line, so with
# pinDigests BASE_TAG becomes "latest@sha256:…". Keep these one per line and do not
# share one ARG between two FROMs.
#
ARG BASE_IMAGE="ghcr.io/ublue-os/kinoite-main"
ARG BASE_TAG="latest@sha256:f49629cc6fcadaaa73da56648809e139f3e0b9eacd24cfdec9b9baef1e6d40e7"

# akmods ships prebuilt, MOK-signed out-of-tree modules built against the *exact*
# kernel in the base. A scratch image with no shell — the RPMs are bind-mounted below.
# akmods-nvidia-open is the same for the NVIDIA driver, and also carries ublue's
# nvidia-install.sh, which build_files/nvidia.sh runs.
#
# NOT PINNED BY RENOVATE. akmods republishes main-44 roughly daily, independently of
# when kinoite-main republishes its own `latest`. Pinning both by digest via two
# separate Renovate rules meant the two pins agreed only by chance — see
# .github/workflows/build.yml's "Resolve matching akmods digest" step. Every real
# build derives the retained kernel-specific akmods tag from the base image's
# `ostree.linux` label, verifies that candidate's label, then pins its digest. It
# fails closed rather than falling back to a floating tag for another kernel.
#
# The Fedora release is NOT set here. The workflows take the flavor from AKMODS_FLAVOR
# and the Fedora release and kernel from the base image's own labels, so a base that
# crosses to a new Fedora release needs no edit (see
# .github/scripts/resolve_akmods_candidate.py). AKMODS_TAG is only the default for a
# direct local build and must be overridden when the base is on a different release.
# The same applies to AKMODS_NVIDIA_TAG, which uses the same AKMODS_FLAVOR.
#
# Every ARG used in a FROM line must be declared before the first FROM.
ARG AKMODS_IMAGE="ghcr.io/ublue-os/akmods"
ARG AKMODS_FLAVOR="main"
ARG AKMODS_TAG="main-44"
ARG AKMODS_NVIDIA_IMAGE="ghcr.io/ublue-os/akmods-nvidia-open"
ARG AKMODS_NVIDIA_TAG="main-44"
FROM ${AKMODS_IMAGE}:${AKMODS_TAG} AS akmods
FROM ${AKMODS_NVIDIA_IMAGE}:${AKMODS_NVIDIA_TAG} AS akmods_nvidia

FROM scratch AS ctx
COPY build_files /build_files
COPY system_files /system_files
# Baked in so the installed system verifies its own upgrades (see 85-signing.sh).
COPY cosign.pub /cosign.pub

FROM ${BASE_IMAGE}:${BASE_TAG}

ARG IMAGE_NAME="vespera"
ARG IMAGE_VENDOR="abirkel"
ARG IMAGE_REGISTRY="ghcr.io/abirkel"
ARG VERSION_TAG=""
# The always-built tag for this run (testing on the daily/CI path; latest only ever
# moves via promote.yml, never via a build). Recorded into image-info.json so
# rebase-helper style tooling knows which stream produced this image.
ARG IMAGE_TAG="testing"
# Opt-in extras. Set to 0 in the workflow to skip.
ARG ENABLE_MSFONTS="1"
ARG ENABLE_YEETMOUSE="1"

# nvidia.sh runs first, before 00-dnf-policy.sh, so the NVIDIA set resolves as it did
# in kinoite-nvidia. 99-cleanup.sh's cleanup and commit cover both.
RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=bind,from=akmods,source=/rpms,target=/tmp/akmods-rpms \
    --mount=type=bind,from=akmods_nvidia,source=/rpms,target=/tmp/akmods-nv-rpms \
    --mount=type=cache,target=/var/cache/libdnf5,sharing=locked \
    --mount=type=tmpfs,target=/tmp \
    --mount=type=tmpfs,target=/var/log \
    /ctx/build_files/nvidia.sh && /ctx/build_files/build.sh

# Lint last and offline, so nothing can reach the network at this point.
RUN --network=none --mount=type=tmpfs,target=/tmp bootc container lint

CMD ["/sbin/init"]
