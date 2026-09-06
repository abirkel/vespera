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
# FATAL if it cannot be installed. The kmod package name embeds the exact kernel version
# and Provides `kernel-modules-for-kernel = <exact kver>`, so it only resolves when
# abirkel-stable has a build for the kernel this base ships. Shipping an image where the
# mouse driver is silently absent is not acceptable, so the build stops instead.
#
# CONSEQUENCE, and the reason the schedule in build.yml is 07:00 rather than 05:20:
# abirkel/yeetmouse-rpm builds kmods for the current ublue kernel at 06:00 UTC. Any run
# that starts before that on a day the kernel moved will find no matching kmod and now
# fails. Re-dispatch after yeetmouse-rpm has published, or set ENABLE_YEETMOUSE=0 for a
# local build that deliberately does without it.
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
        # Print the diagnostic BEFORE dying, so the log says which kernels are available
        # rather than just that this one is not.
        printf '\n' >&2
        printf 'kmod-yeetmouse builds present in abirkel-stable:\n' >&2
        dnf5 repoquery --disablerepo='*' --enablerepo='abirkel-stable' \
            --qf '    %{name}\n' 'kmod-yeetmouse*' 2>/dev/null \
            | grep -v '\.src' | sort -u >&2 || true
        printf '\n' >&2
        die "no kmod-yeetmouse build for ${KVER} in abirkel-stable.
  Build one there (its check-release workflow runs 06:00 UTC daily, or dispatch it
  manually), then re-run this build. ENABLE_YEETMOUSE=0 skips yeetmouse entirely."
    fi

    dnf5 -y config-manager setopt 'abirkel-stable'.enabled=0
fi
