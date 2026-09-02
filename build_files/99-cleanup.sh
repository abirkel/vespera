#!/usr/bin/bash
# Cleanup and pre-lint checks.
source "${CTX}/build_files/lib/common.sh"

# ---------------------------------------------------------------------------
# Every repo added here must be disabled in the shipped image. negativo17 and akmods
# come from base packages and stay as the base left them.
# ---------------------------------------------------------------------------
log "Disabling third-party repositories"
for repo in terra terra-extras terra-source terra-extras-source abirkel-stable; do
    if dnf5 repolist --all 2>/dev/null | grep -qE "^${repo}\s"; then
        dnf5 -y config-manager setopt "${repo}".enabled=0 || true
    fi
done
# copr_install already disables each, but be defensive.
for f in /etc/yum.repos.d/_copr*.repo; do
    [[ -e "$f" ]] || continue
    sed -i 's/^enabled=1/enabled=0/' "$f"
done

log "Repository state in the shipped image"
dnf5 repolist --enabled 2>/dev/null | sed 's/^/    /' || true
# The ublue akmods COPR is enabled by the base at priority 85, which is expected.
# Anything else third-party and enabled is a bug.
enabled_bad="$(dnf5 repolist --enabled 2>/dev/null \
    | tail -n +2 | awk '{print $1}' \
    | grep -viE '^(fedora|updates|fedora-cisco|copr:.*ublue-os:akmods)' || true)"
if [[ -n "${enabled_bad}" ]]; then
    warn "unexpected enabled repos in the shipped image:"
    printf '    %s\n' ${enabled_bad}
fi

# ---------------------------------------------------------------------------
# Sanity checks: the things that break silently and are painful to find after deploy.
# ---------------------------------------------------------------------------
log "Sanity checks"

# All four Discover backends. The rpm-ostree one is why this image is on Kinoite
# rather than Bazzite, and it is NOT in the base — kinoite-main excludes it, so
# 10-packages-fedora.sh installs it back. A failure here means that install broke.
for backend in flatpak rpm-ostree fwupd kns; do
    [[ -e "/usr/lib64/qt6/plugins/discover/${backend}-backend.so" ]] \
        || die "Discover ${backend} backend missing"
done
info "Discover: flatpak, rpm-ostree, fwupd, kns backends present"

# The 32-bit driver stack is what makes native Steam and 32-bit Proton work.
for lib in /usr/lib/libnvidia-glcore.so.* /usr/lib/libGLX_nvidia.so.*; do
    [[ -e "$lib" ]] && { info "32-bit NVIDIA libs present"; break; }
done
i686_count="$(rpm -qa --qf '%{ARCH}\n' | grep -c '^i686$' || true)"
(( i686_count > 100 )) || warn "only ${i686_count} i686 packages; 32-bit gaming may be broken"
info "i686 packages: ${i686_count}"

# No Docker, no Bazaar, no cockpit — all explicitly out of scope. `pulseaudio` is
# in this list because 60-system-config.sh symlinks /usr/bin/pulseaudio to
# /usr/bin/true; that path is owned by the (uninstalled) pulseaudio package, so if
# anything ever pulls it in, our symlink and its file would collide.
for unwanted in docker-ce containerd.io bazaar cockpit-ws lutris obs-studio solaar pulseaudio; do
    rpm -q "${unwanted}" >/dev/null 2>&1 && warn "unexpected package present: ${unwanted}"
done

# We must not have appended to the package-owned justfile.
if rpm -V ublue-os-just 2>/dev/null | grep -q 'usr/share/ublue-os/justfile'; then
    die "the shipped ublue-os justfile was modified; use 60-custom.just instead"
fi

# Nor clobbered any other package-owned config. The Qt logging override lives in
# /etc/xdg/QtProject/ so qt{5,6}-qtbase stay pristine; rpm -V is where a regression
# would show up.
# Two accepted exceptions:
#   /etc/skel/.zshrc            - deliberate clobber (see that file's header: zsh's own
#                                 version is 34 lines of commented examples, and its whole
#                                 startup chain is package-owned with no drop-in dir).
#   /usr/lib/kernel/install.conf - modified by the base image, not by this build. ublue sets
#                                 layout=ostree there so rpm-ostree owns dracut. Verified
#                                 byte-identical (same sha256) in kinoite-nvidia:44 and in
#                                 the built image, so it carries no signal about our layer.
# Anything else modified in these packages is a surprise worth seeing.
for pkg in qt5-qtbase qt6-qtbase systemd-udev zsh; do
    rpm -q "$pkg" >/dev/null 2>&1 || continue
    modified="$(rpm -V "$pkg" 2>/dev/null | grep -E '^..5' \
        | grep -vF '/etc/skel/.zshrc' \
        | grep -vF '/usr/lib/kernel/install.conf' || true)"
    [[ -z "$modified" ]] || warn "${pkg} has unexpected modified files:
${modified}"
done
[[ -f /etc/xdg/QtProject/qtlogging.ini ]] \
    || warn "/etc/xdg/QtProject/qtlogging.ini missing; Qt debug spam will not be suppressed"

# environment.d cannot express a conditional, so the binary it points at is asserted here.
[[ -x /usr/bin/ksshaskpass ]] \
    || warn "ksshaskpass missing but environment.d sets SUDO_ASKPASS to it; sudo -A will fail"

# GameMode's renice needs this group to exist; 10-groups.sh joins users at boot.
grep -q '^gamemode:' /usr/lib/group \
    || warn "gamemode group missing from /usr/lib/group; GameMode renice will be a no-op"

[[ -f /usr/share/ublue-os/just/60-custom.just ]] \
    || warn "60-custom.just missing; custom ujust recipes will not load"
info "ujust: 60-custom.just in place, shipped justfile untouched"

# A typo in a recipe must not ship.
if command -v just >/dev/null 2>&1; then
    just --justfile /usr/share/ublue-os/justfile --unstable --summary >/dev/null \
        && info "ujust recipes parse cleanly" \
        || die "ujust recipe syntax error"
fi

# ---------------------------------------------------------------------------
# Filesystem cleanup for bootc.
# ---------------------------------------------------------------------------
log "Cleaning up"
dnf5 -y config-manager setopt keepcache=0
dnf5 clean all || true

# libguestfs pulls syslinux-extlinux, which writes to /boot and trips bootc lint.
# shellcheck disable=SC2115  # literal path, no variable expansion involved
rm -rf /boot/* /boot/.[!.]* 2>/dev/null || true

# /tmp is a tmpfs mount, so nothing here can reach the image; this is belt-and-braces
# for the day that mount is dropped. The warnings file MUST survive: it lives in /tmp and
# build.sh reads it after this script returns to print the end-of-build summary. A blanket
# rm here silently emptied it, so every warning raised anywhere in the build was reported
# as "no warnings" (found by an actual build, not by reading).
# -maxdepth 1 keeps this equivalent to the old `rm -rf /tmp/*` and stops find recursing
# into /tmp/akmods-rpms, which is a read-only bind mount of the akmods image.
find /tmp -mindepth 1 -maxdepth 1 ! -name "${WARNINGS_FILE##*/}" \
    -exec rm -rf {} + 2>/dev/null || true
rm -rf /var/log/* 2>/dev/null || true

# Restore /var to the state the base ships: nothing but /var/tmp. Everything else there
# is machine state that tmpfiles.d recreates on first boot, and bootc lint flags it if
# committed. /var/cache is skipped because /var/cache/libdnf5 is a live mount (rm would
# hit EBUSY). Alternatives are not a concern: Fedora keeps that database in
# /etc/alternatives-admindir, not /var/lib/alternatives (verified).
find /var -mindepth 1 -maxdepth 1 ! -name tmp ! -name cache \
    -exec rm -rf {} + 2>/dev/null || true
find /var/cache -mindepth 1 -maxdepth 1 ! -name libdnf5 \
    -exec rm -rf {} + 2>/dev/null || true
install -d -m1777 /var/tmp

ostree container commit

log "Cleanup complete"
