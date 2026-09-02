#!/usr/bin/bash
# Out-of-tree kernel modules. These must match the base kernel EXACTLY.
#
# The kernel is never replaced: kinoite-nvidia ships Fedora's kernel rebuilt and
# signed with the ublue MOK, which is what lets prebuilt signed kmods load under
# Secure Boot. A kernel swap here would break that chain.
source "${CTX}/build_files/lib/common.sh"

KVER="$(kernel_version)"
log "Installing kmods for kernel ${KVER}"

# ---------------------------------------------------------------------------
# Is the akmods image for the right Fedora release?
#
# BASE_TAG is `latest`, so the base rolls to Fedora N+1 on its own, but akmods has no
# rolling tag and AKMODS_TAG names a release explicitly. If the base crosses to F45
# while AKMODS_TAG says main-44, no kmod can match — and the only symptom would be a
# virtual camera that quietly stopped existing.
#
# A warning, not a failure: a stale akmods costs one optional module, and blocking
# every security update over that is the wrong trade.
# ---------------------------------------------------------------------------
base_fedora="$(fedora_version)"
akmods_fedora="$(
    find "${AKMODS_RPMS}" -name '*.rpm' -printf '%f\n' 2>/dev/null \
        | grep -oE '\.fc[0-9]+\.' | grep -oE '[0-9]+' | sort -u | head -1
)"
if [[ -z "${akmods_fedora}" ]]; then
    warn "could not determine the akmods image's Fedora version; kmods may be skipped"
elif [[ "${akmods_fedora}" != "${base_fedora}" ]]; then
    warn "AKMODS IMAGE IS OUT OF SYNC WITH THE BASE.
    base image  : Fedora ${base_fedora}
    akmods image: Fedora ${akmods_fedora}
    ACTION: edit the Containerfile and set
        ARG AKMODS_TAG=\"main-${base_fedora}\"
    Until then v4l2loopback (virtual camera) will not be installed. Everything
    else in this image is unaffected."
else
    info "akmods image matches the base: Fedora ${base_fedora}"
fi

# ---------------------------------------------------------------------------
# v4l2loopback — virtual video device, for any "use this app as a webcam" workflow.
# From ghcr.io/ublue-os/akmods (`main`, matching Fedora's kernel), bind-mounted by the
# Containerfile. Two halves: the userspace package and the kmod for this exact kernel.
# ---------------------------------------------------------------------------
v4l2_common=( "${AKMODS_RPMS}"/common/v4l2loopback-*.rpm )
v4l2_kmod=( "${AKMODS_RPMS}/kmods/kmod-v4l2loopback-${KVER}-"*.rpm )

if [[ -f "${v4l2_common[0]:-}" && -f "${v4l2_kmod[0]:-}" ]]; then
    dnf5 -y install "${v4l2_common[0]}" "${v4l2_kmod[0]}"
    info "v4l2loopback installed for ${KVER}"
else
    warn "v4l2loopback: no akmods build for ${KVER}; virtual camera will not work"
    info "  looked for: ${AKMODS_RPMS}/kmods/kmod-v4l2loopback-${KVER}-*.rpm"
    ls -1 "${AKMODS_RPMS}/kmods/" 2>/dev/null | sed 's/^/  available: /' || true
fi

# Load it on boot but keep it inert until something opens it.
install -Dm0644 /dev/stdin /usr/lib/modules-load.d/v4l2loopback.conf <<'EOF'
v4l2loopback
EOF
install -Dm0644 /dev/stdin /usr/lib/modprobe.d/v4l2loopback.conf <<'EOF'
# exclusive_caps=1 is required for Chromium/Firefox to see it as a capture device.
options v4l2loopback devices=1 exclusive_caps=1 card_label="Virtual Camera"
EOF

# ---------------------------------------------------------------------------
# yeetmouse — raw mouse-input accel driver, from the abirkel-stable repo.
#
# FRAGILE, verified: the kmod package name embeds the kernel version and Provides
# `kernel-modules-for-kernel = <exact kver>`. abirkel-stable publishes builds for
# 7.1.4 through 7.1.9 plus ogc, but not 7.1.10-200.fc44, which the base ships today.
#
# So a SOFT failure: the image still builds and warns. ENABLE_YEETMOUSE=0 skips it
# entirely; flip the `warn` to `die` to block until the repo catches up.
# ---------------------------------------------------------------------------
if [[ "${ENABLE_YEETMOUSE:-1}" != "1" ]]; then
    info "yeetmouse: disabled by ENABLE_YEETMOUSE=0"
else
    log "yeetmouse (abirkel-stable)"
    dnf5 -y config-manager addrepo --overwrite \
        --from-repofile=https://abirkel.github.io/rpm-repo/abirkel-stable.repo

    if dnf5 -y install --enable-repo='abirkel-stable' \
            "kmod-yeetmouse-${KVER}" yeetmouse; then
        info "yeetmouse installed for ${KVER}"
    else
        warn "yeetmouse: no kmod build for ${KVER} in abirkel-stable — SKIPPED."
        warn "  Rebuild against ${KVER} and re-run."
        info "  Available builds:"
        dnf5 repoquery --disablerepo='*' --enablerepo='abirkel-stable' \
            --qf '    %{name}\n' 'kmod-yeetmouse*' 2>/dev/null \
            | grep -v '\.src' | sort -u || true
    fi

    dnf5 -y config-manager setopt 'abirkel-stable'.enabled=0
fi
