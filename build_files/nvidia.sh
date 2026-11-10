#!/usr/bin/bash
# NVIDIA driver layer: what ublue's retired kinoite-nvidia added on top of kinoite-main.
#
# ublue built kinoite-nvidia by running nvidia-install.sh from the akmods-nvidia-open
# image on kinoite-main, then regenerating the initramfs. This does the same, with the
# script and RPMs from the akmods-nvidia-open image the Containerfile mounts. The
# kmod is prebuilt and signed with ublue's MOK, like the kernel, so Secure Boot keeps
# working with no new key.
#
# Runs before build.sh, and so before 00-dnf-policy.sh: the NVIDIA set resolves with
# the same weak-deps setting kinoite-nvidia used. Not a numbered script for that reason.
# 99-cleanup.sh's /var cleanup and `ostree container commit` cover this step too.
#
# IMAGE_NAME is "vespera", so the installer's kinoite/silverblue branch skips
# supergfxctl, which is for hybrid-graphics laptops.
export CTX=/ctx
# shellcheck source=lib/common.sh
source "${CTX}/build_files/lib/common.sh"

export AKMODNV_PATH=/tmp/akmods-nv-rpms

KVER="$(kernel_version)"
log "Installing the NVIDIA driver for kernel ${KVER}"

# shellcheck source=/dev/null
source "${AKMODNV_PATH}/kmods/nvidia-vars"
[[ "${KERNEL_VERSION}" == "${KVER}" ]] \
    || die "akmods-nvidia-open was built for ${KERNEL_VERSION}, but the base ships ${KVER}"

# The installer reads IMAGE_NAME (a build ARG, so already in the environment).
export IMAGE_NAME
"${AKMODNV_PATH}/ublue-os/nvidia-install.sh"

rpm -q --whatprovides "kmod-nvidia-${KVER}" >/dev/null \
    || die "no kmod-nvidia installed for ${KVER}"
modinfo -k "${KVER}" nvidia >/dev/null \
    || die "the nvidia module for ${KVER} is not loadable by modinfo"

# The installer disables these after use. Left enabled, they could shadow Fedora or
# negativo17 packages in later transactions, and 99-cleanup.sh's allowlist accepts any
# repo id starting with "fedora", so it would not catch fedora-nvidia*.
enabled="$(dnf5 repolist --enabled 2>/dev/null | awk 'NR>1 {print $1}')"
if grep -E '^(fedora-nvidia|nvidia-container-toolkit$|copr:copr\.fedorainfracloud\.org:ublue-os:staging$)' \
        <<<"${enabled}"; then
    die "nvidia-install.sh left the repos above enabled"
fi

# Same invocation as ublue's initramfs.sh. The installer switched 99-nvidia.conf to
# force_drivers, so the driver loads from the initramfs.
log "Regenerating the initramfs"
initramfs="/usr/lib/modules/${KVER}/initramfs.img"
export DRACUT_NO_XATTR=1
dracut --no-hostonly --kver "${KVER}" --reproducible --add ostree -f "${initramfs}"
chmod 0600 "${initramfs}"

# Written to a file first: `lsinitrd | grep -q` can fail under pipefail when grep
# exits early.
lsinitrd "${initramfs}" >/tmp/initramfs-contents
grep -q '/nvidia\.ko' /tmp/initramfs-contents || die "the initramfs has no nvidia module"

info "NVIDIA $(rpm -q --qf '%{VERSION}' nvidia-driver) installed for ${KVER}"
