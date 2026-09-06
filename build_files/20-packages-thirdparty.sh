#!/usr/bin/bash
# Third-party repositories, each enabled for a single transaction and left disabled.
source "${CTX}/build_files/lib/common.sh"

# ---------------------------------------------------------------------------
# negativo17 — configured in the base, shipped disabled.
# ---------------------------------------------------------------------------
log "negativo17: media extras"
repo_install 'fedora-multimedia' \
    makemkv \
    rar

# Point libaacs/libbdplus at MakeMKV's libmmbd so encrypted discs play. The
# non-obvious half: the packages alone do not enable playback.
for lib in libaacs.so.0 libaacs.so.0.7.2 libbdplus.so.0 libbdplus.so.0.2.0; do
    ln -sf /usr/lib64/libmmbd.so.0 "/usr/lib64/${lib}"
done
# A CLI dependency here, not an app to surface.
[[ -f /usr/share/applications/makemkv.desktop ]] &&
    desktop-file-edit --set-key=Hidden --set-value=true \
        /usr/share/applications/makemkv.desktop || true
info "libaacs/libbdplus wired to libmmbd"

# ---------------------------------------------------------------------------
# Terra (Fyra Labs).
#
# GPG GOTCHA. Terra sets gpgcheck=1 and repo_gpgcheck=1, and dnf5 verifies repomd.xml
# against its OWN key store — `rpm --import` does not satisfy it. `--assumeyes` does:
# dnf5 prompts "Importing OpenPGP key 0xDE226D6F: ... Is this ok [y/N]" and -y answers
# it, importing from the `gpgkey=` file. repo_install always passes -y.
#
# The trap is DIAGNOSTIC, not build-time. `dnf5 repoquery` has no -y, so it always
# fails that prompt and reports Terra as having ZERO packages:
#     >>> repomd.xml GPG signature verification error: Signing key not found
# which looks exactly like a broken repo. Verified both ways. If a Terra package
# "does not exist", try an install rather than a repoquery.
# ---------------------------------------------------------------------------
log "Terra: gaming + cooling packages"
dnf5 -y install --nogpgcheck \
    --repofrompath "terra,https://repos.fyralabs.com/terra\$releasever" \
    terra-release terra-release-extras

# Nine packages, ~39 MiB, measured with install_weak_deps=False.
repo_install 'terra*' \
    umu-launcher umu-wrapper \
    vulkan-low-latency-layer \
    dmemcg-booster kcgroups-dmemcg plasma-foreground-booster-dmemcg \
    coolercontrol coolercontrold

# ---------------------------------------------------------------------------
# ScopeBuddy — a bash wrapper around gamescope keeping per-game flags in a config file
# instead of Steam launch options. Two scripts, a README and a LICENSE; that is all.
#
# PROVENANCE: package from Terra; the --nodeps decision is ours. Bazzite installs it
#   normally and eats the perl dependency. Audit by re-reading the shipped scripts —
#   the assertions below do exactly that.
#
# --nodeps IS DELIBERATE. Its spec declares `Requires: perl`, the full metapackage,
# resolving to +196 packages / +268 MiB including perl-CPAN, gcc, libstdc++-devel,
# kernel-headers and every *-srpm-macros.
#
# None of it is used. perl appears in exactly three places (~lines 405, 411, 521) as
# `perl -pe` one-liners extracting an app id; only the /usr/bin/perl binary is needed.
# Everything else is bash, jq, gawk, sed, grep and gamescope — and perl-interpreter
# and gawk are already in the base, measured at zero packages added. Net cost: 1.
#
# Every real runtime dependency is asserted rather than trusting --nodeps blindly.
# ---------------------------------------------------------------------------
log "ScopeBuddy (bypassing its over-broad 'Requires: perl')"

for dep in /usr/bin/perl /usr/bin/gawk /usr/bin/jq /usr/bin/sed /usr/bin/grep /usr/bin/bash; do
    [[ -x "$dep" ]] || die "ScopeBuddy runtime dependency missing: ${dep}"
done
rpm -q gamescope >/dev/null 2>&1 || die "ScopeBuddy needs gamescope, which 10-packages-fedora.sh should have installed"

scb_tmp="$(mktemp -d)"
if dnf5 -y download --enable-repo='terra*' --destdir="${scb_tmp}" ScopeBuddy; then
    # MUST exclude the SRPM. `dnf5 download` writes BOTH
    # ScopeBuddy-0:1.5.0-3.fc44.noarch.rpm and ...src.rpm into destdir, even though the
    # terra-source repos are disabled (verified). A bare ScopeBuddy-*.rpm glob therefore
    # hands rpm the source package too, which fails with
    #   "failed to open dir root of /root/rpmbuild/SOURCES/: cpio: mkdir failed"
    # and takes the whole build down. Found by an actual build, not by reading.
    mapfile -t scb_rpms < <(
        find "${scb_tmp}" -maxdepth 1 -name 'ScopeBuddy-*.rpm' ! -name '*.src.rpm'
    )
    (( ${#scb_rpms[@]} == 1 )) \
        || die "expected exactly 1 ScopeBuddy binary RPM, found ${#scb_rpms[@]}: ${scb_rpms[*]}"
    rpm -Uvh --nodeps "${scb_rpms[0]}"
    # Prove the bypass was safe: the scripts must exist and be runnable.
    [[ -x /usr/bin/scopebuddy && -x /usr/bin/scb ]] \
        || die "ScopeBuddy installed but its scripts are missing"
    if ! grep -qE '^\s*#!/usr/bin/bash' /usr/bin/scopebuddy; then
        warn "scopebuddy is no longer a bash script; re-check whether --nodeps is still safe"
    fi
    # Perl MODULES, rather than just the binary, would make --nodeps unsafe.
    if grep -qE '^\s*(use|require)\s+[A-Z]' /usr/bin/scopebuddy; then
        warn "scopebuddy now uses perl modules; --nodeps may be unsafe — review its Requires"
    fi
    info "installed $(rpm -q ScopeBuddy) — 1 package instead of 197"
else
    warn "ScopeBuddy: download failed; skipped"
fi
rm -rf "${scb_tmp}"

# Confirm gamescope is still Fedora's build, not Terra's.
info "gamescope: $(rpm -q gamescope)"

# Leave Terra disabled in the shipped image.
dnf5 -y config-manager setopt 'terra*'.enabled=0
info "Terra disabled again"

# ---------------------------------------------------------------------------
# COPRs, each isolated to one transaction.
# ---------------------------------------------------------------------------
log "COPR packages"

# ublue's own supporting packages.
#   ublue-setup-services          the hooks.d runners our hooks depend on
#   ublue-os-libvirt-workarounds  SELinux labelling + socket ordering for libvirt
#   ublue-os-media-automount-udev auto-mounts internal partitions under /media
#   ublue-os-selinux-workarounds  policy fixes all three ublue images adopted
copr_install "ublue-os/packages" \
    ublue-setup-services \
    ublue-os-libvirt-workarounds \
    ublue-os-media-automount-udev \
    ublue-os-selinux-workarounds

copr_install "ledif/kairpods"           kairpods
copr_install "major-tom/klassy"         klassy
copr_install "fuddlesworth/PlasmaZones" plasmazones

# ---------------------------------------------------------------------------
# Valve's Vapor look-and-feel, without the branding hijack.
#
# steamdeck-kde-presets-desktop ships the Vapor/VGUI colour schemes, desktop theme,
# Konsole profile and look-and-feel packages — but also overwrites
# /etc/xdg/{kdeglobals,kscreenlockerrc,ktrashrc} and the GTK settings, forcing the
# theme system-wide over stock Kinoite defaults. Keep the themes, delete the
# overrides, and Vapor becomes selectable rather than imposed.
# ---------------------------------------------------------------------------
log "Vapor theme (themes only, no forced defaults)"
copr_install "ublue-os/bazzite" steamdeck-kde-presets-desktop

# DERIVED, NOT HARDCODED. Delete every /etc file the package owns — those are the
# defaults it imposes. A hardcoded list of today's five would silently start forcing
# the theme again the day upstream adds a sixth. Everything under /usr/share is left
# alone, which is the half worth keeping.
mapfile -t forced < <(rpm -ql steamdeck-kde-presets-desktop 2>/dev/null | grep '^/etc/')
if (( ${#forced[@]} == 0 )); then
    warn "steamdeck-kde-presets-desktop owns no /etc files; the theme may now be forced differently — re-check"
else
    for f in "${forced[@]}"; do
        [[ -f "$f" ]] || continue
        rm -f "$f"
        info "removed forced default: ${f}"
    done
fi

# Assert the kept half is present, so "themes only" cannot become "nothing at all".
if compgen -G "/usr/share/color-schemes/V*.colors" >/dev/null; then
    info "Vapor/VGUI colour schemes present and selectable in System Settings"
else
    warn "Vapor colour schemes missing; steamdeck-kde-presets-desktop layout changed"
fi

# Sanity check: stock Kinoite branding must be intact.
grep -q '^NAME="Fedora Linux"' /usr/lib/os-release \
    || die "os-release NAME was modified; branding must stay stock"

# ---------------------------------------------------------------------------
# cicpoffs — case-insensitive overlay FUSE fs, for games assuming Windows path
# semantics. Not in any repo; published as a GitHub release RPM.
#
# NOT PINNABLE: ublue-os/cicpoffs publishes one rolling release tagged literally
# `master`, assets re-uploaded in place (verified). Nothing to pin, nothing for
# Renovate to bump — this one download is deliberately not reproducible. Fetched from
# the stable /releases/download/master/ URL rather than the API, which is rate-limited
# per IP and fails on shared CI runners.
#
# UNSIGNED, deliberately accepted: the published RPM carries no OpenPGP signature at all
# (verified — `rpm -qip` reports "Signature: (none)"), so there is nothing to verify it
# against and dnf logs "skipped OpenPGP checks ... @commandline" for it. The trust anchor
# is TLS to github.com/ublue-os, which is the same organisation whose base image this whole
# build already rests on, so it widens the trust boundary by nothing.
# ---------------------------------------------------------------------------
log "cicpoffs (GitHub rolling release)"
FEDORA_MAJOR="$(fedora_version)"
readonly FEDORA_MAJOR
readonly CICPOFFS_RPM="cicpoffs-fc${FEDORA_MAJOR}.rpm"
readonly CICPOFFS_URL="https://github.com/ublue-os/cicpoffs/releases/download/master/${CICPOFFS_RPM}"
tmp="$(mktemp -d)"
if fetch -o "${tmp}/${CICPOFFS_RPM}" "${CICPOFFS_URL}"; then
    dnf5 -y install "${tmp}/${CICPOFFS_RPM}"
    info "installed $(rpm -q cicpoffs)"
else
    warn "cicpoffs: ${CICPOFFS_RPM} not published yet for fc${FEDORA_MAJOR}; skipped"
fi
rm -rf "${tmp}"
