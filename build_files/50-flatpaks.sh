#!/usr/bin/bash
# Flatpak configuration. The declarations live in
# system_files/usr/share/flatpak/preinstall.d/ and are copied in by 60-system-config.sh;
# this script only validates them. The unit is enabled in 70-services.sh.
source "${CTX}/build_files/lib/common.sh"

log "Validating Flatpak preinstall declarations"

shopt -s nullglob
files=( "${SYSTEM_FILES}"/usr/share/flatpak/preinstall.d/*.preinstall )
shopt -u nullglob
(( ${#files[@]} )) || die "no *.preinstall files found in system_files"

# Every stanza header must be well formed and declare a Branch. A typo here would
# otherwise only surface as a silent no-op on first boot.
for f in "${files[@]}"; do
    n_hdr=$(grep -c '^\[Flatpak Preinstall [A-Za-z0-9._-]\+\]$' "$f" || true)
    n_br=$(grep -c '^Branch=' "$f" || true)
    (( n_hdr > 0 )) || die "$(basename "$f"): no valid [Flatpak Preinstall <ref>] stanzas"
    (( n_hdr == n_br )) || die "$(basename "$f"): ${n_hdr} stanzas but ${n_br} Branch= lines"
    info "$(basename "$f"): ${n_hdr} refs"
done

# Flathub is already configured by the base (kinoite-main ships the .flatpakrepo and
# enables it via flatpak-add-fedora-repos.service, with the Fedora remotes disabled).
# Asserted so a base change is caught loudly.
[[ -f /etc/flatpak/remotes.d/flathub.flatpakrepo ]] \
    || die "base no longer ships the Flathub remote definition"

info "Flathub remote definition present; unit enabled in 70-services.sh"
