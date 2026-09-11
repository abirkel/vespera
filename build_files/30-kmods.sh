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
# v4l2loopback — virtual video device, for any "use this app as a webcam" workflow.
# From ghcr.io/ublue-os/akmods (`main`, matching Fedora's kernel), bind-mounted by the
# Containerfile. Two halves: the userspace package and the kmod for this exact kernel.
#
# FATAL if missing. This is a required driver, not an optional extra.
#
# BASE_TAG is `latest`, so the base rolls to Fedora N+1 on its own, but akmods has no
# rolling tag and AKMODS_TAG names a release explicitly. If the base crosses to F45
# while AKMODS_TAG says main-44, no kmod can match. Fedora-release matching alone is
# also not enough: akmods and the base image can be on the same Fedora release but
# different kernel builds (e.g. base on 7.1.13-200.fc44 while akmods only has
# 7.2.4-200.fc44), in which case the kmod filename simply will not match KVER. Both
# cases must stop the build rather than silently ship without the virtual camera.
#
# CONSEQUENCE: akmods has no schedule tying it to kinoite-nvidia's own kernel bumps,
# so a Renovate digest bump on akmods can land ahead of the base image picking up the
# matching kernel. If a build fails here right after an akmods digest bump, that is
# almost certainly why. Re-dispatch once the base image's next rebuild lands the same
# kernel, or pin AKMODS_TAG back to a digest whose kernel matches KVER, or set
# ENABLE_V4L2LOOPBACK=0 for a local build that deliberately does without it.
# ---------------------------------------------------------------------------
if [[ "${ENABLE_V4L2LOOPBACK:-1}" != "1" ]]; then
    info "v4l2loopback: disabled by ENABLE_V4L2LOOPBACK=0"
else
    base_fedora="$(fedora_version)"
    akmods_fedora="$(
        find "${AKMODS_RPMS}" -name '*.rpm' -printf '%f\n' 2>/dev/null \
            | grep -oE '\.fc[0-9]+\.' | grep -oE '[0-9]+' | sort -u | head -1
    )"
    if [[ -z "${akmods_fedora}" ]]; then
        die "could not determine the akmods image's Fedora version; cannot verify
  v4l2loopback compatibility. Check that ${AKMODS_RPMS} was mounted correctly."
    elif [[ "${akmods_fedora}" != "${base_fedora}" ]]; then
        die "AKMODS IMAGE IS OUT OF SYNC WITH THE BASE.
  base image  : Fedora ${base_fedora}
  akmods image: Fedora ${akmods_fedora}
  ACTION: edit the Containerfile and set
      ARG AKMODS_TAG=\"main-${base_fedora}\"
  v4l2loopback (virtual camera) is a required driver for this image. The build
  stops rather than shipping without it. ENABLE_V4L2LOOPBACK=0 skips this driver
  entirely for a deliberate local build without it."
    else
        info "akmods image matches the base: Fedora ${base_fedora}"
    fi

    v4l2_common=( "${AKMODS_RPMS}"/common/v4l2loopback-*.rpm )
    v4l2_kmod=( "${AKMODS_RPMS}/kmods/kmod-v4l2loopback-${KVER}-"*.rpm )

    if [[ -f "${v4l2_common[0]:-}" && -f "${v4l2_kmod[0]:-}" ]]; then
        dnf5 -y install "${v4l2_common[0]}" "${v4l2_kmod[0]}"
        info "v4l2loopback installed for ${KVER}"
    else
        printf '\n' >&2
        printf 'kmod-v4l2loopback builds present in the akmods image:\n' >&2
        ls -1 "${AKMODS_RPMS}/kmods/" 2>/dev/null | grep -i v4l2loopback | sed 's/^/  /' >&2 || true
        printf '\n' >&2
        die "no kmod-v4l2loopback build for kernel ${KVER}; virtual camera would be
  missing. Looked for: ${AKMODS_RPMS}/kmods/kmod-v4l2loopback-${KVER}-*.rpm
  This usually means the pinned AKMODS_TAG in the Containerfile has moved to a
  newer kernel build than the current base image ships. Either wait for the base
  image's next kernel bump to catch up, or pin AKMODS_TAG back to a digest whose
  kernel matches ${KVER}. ENABLE_V4L2LOOPBACK=0 skips this driver entirely for a
  deliberate local build without it."
    fi

    # Load it on boot but keep it inert until something opens it.
    install -Dm0644 /dev/stdin /usr/lib/modules-load.d/v4l2loopback.conf <<'EOF'
v4l2loopback
EOF
    install -Dm0644 /dev/stdin /usr/lib/modprobe.d/v4l2loopback.conf <<'EOF'
# exclusive_caps=1 is required for Chromium/Firefox to see it as a capture device.
options v4l2loopback devices=1 exclusive_caps=1 card_label="Virtual Camera"
EOF
fi

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
