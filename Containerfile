# vespera — a custom KDE gaming + light-dev image on ublue's kinoite-nvidia.
#
# Base is Fedora Kinoite + nvidia-open + a Secure-Boot-signed matching kernel + the
# full 32-bit driver stack + negativo17 codecs. Discover survives here (unlike
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
ARG BASE_IMAGE="ghcr.io/ublue-os/kinoite-nvidia"
ARG BASE_TAG="latest"

# akmods ships prebuilt, MOK-signed out-of-tree modules built against the *exact*
# kernel in the base. A scratch image with no shell — the RPMs are bind-mounted below.
#
# THIS CANNOT FOLLOW AUTOMATICALLY: akmods has no rolling tag, only main-43, main-44, …
# (verified). main-44 rolls forward across F44's kernels, so it needs no attention
# within a release, but when the base crosses to F45 this must become main-45.
#
# The single annual edit here, designed not to bite: 30-kmods.sh compares the Fedora
# version of these RPMs against the base's and warns loudly, naming this line. It does
# NOT fail the build — a stale akmods costs only the virtual-camera module.
ARG AKMODS_IMAGE="ghcr.io/ublue-os/akmods"
ARG AKMODS_TAG="main-44"
FROM ${AKMODS_IMAGE}:${AKMODS_TAG} AS akmods

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
# Opt-in extras. Set to 0 in the workflow to skip.
ARG ENABLE_MSFONTS="1"
ARG ENABLE_YEETMOUSE="1"

RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=bind,from=akmods,source=/rpms,target=/tmp/akmods-rpms \
    --mount=type=cache,target=/var/cache/libdnf5,sharing=locked \
    --mount=type=tmpfs,target=/tmp \
    --mount=type=tmpfs,target=/var/log \
    /ctx/build_files/build.sh

# Lint last and offline, so nothing can reach the network at this point.
RUN --network=none --mount=type=tmpfs,target=/tmp bootc container lint

CMD ["/sbin/init"]
