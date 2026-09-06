#!/usr/bin/bash
# Copies system_files/ into the image, then applies what has to be imperative:
# SELinux booleans, firewalld, desktop-file edits, /etc hygiene.
source "${CTX}/build_files/lib/common.sh"

log "Copying system_files into the image"
sync_files
info "system_files applied"

# ---------------------------------------------------------------------------
# Create the groups sysusers.d declares now, at build time.
#
# sysusers.d is normally processed on first boot, writing to /etc — machine state, and
# too late: 10-groups.sh copies definitions out of /usr/lib/group, and the /etc hygiene
# step at the bottom of this script is what puts them there.
# ---------------------------------------------------------------------------
log "Creating image-provided groups"
systemd-sysusers /usr/lib/sysusers.d/vespera-groups.conf
# plugdev is ours; usershares comes from samba-usershares' own sysusers.d.
for g in plugdev usershares; do
    getent group "$g" >/dev/null || die "group ${g} was not created by sysusers"
    info "$(getent group "$g")"
done

# ---------------------------------------------------------------------------
# Firefox: RPM out, Flatpak in (declared in preinstall.d). The desktop ID is identical
# and mimeapps.list is owned by shared-mime-info, not firefox, so http/https handlers
# keep working untouched. Verified: removes exactly 2 packages.
# ---------------------------------------------------------------------------
log "Removing the Firefox RPM in favour of the Flatpak"
if rpm -q firefox >/dev/null 2>&1; then
    dnf5 -y remove firefox firefox-langpacks
    info "firefox RPM removed"
else
    info "firefox RPM not present"
fi
# Confirm the handler survived — the whole argument for not rewriting mimeapps.
grep -q '^x-scheme-handler/https=org.mozilla.firefox.desktop' \
    /usr/share/applications/mimeapps.list \
    || warn "https handler is not org.mozilla.firefox.desktop; check mimeapps.list"

# ---------------------------------------------------------------------------
# supergfxctl is for hybrid-graphics laptops; this is a single-dGPU desktop.
# ---------------------------------------------------------------------------
if rpm -q supergfxctl >/dev/null 2>&1; then
    log "Removing supergfxctl (laptop hybrid graphics only)"
    systemctl disable supergfxd.service 2>/dev/null || true
    dnf5 -y remove supergfxctl
fi

# ---------------------------------------------------------------------------
# Samba: only the parts the samba-usershares package does NOT do.
#
# Verified: samba-usershares is installed in the base and already ships
# /etc/samba/usershares.conf (included from smb.conf), the `usershares` group via
# sysusers.d, and /var/lib/samba/usershares. The directory is also recreated at every
# boot by /usr/lib/tmpfiles.d/rpm-ostree-autovar.conf as
# `d /var/lib/samba/usershares 1770 root usershares`. Creating it here was dead code
# twice over — the package owns it, and 99-cleanup.sh wipes /var anyway.
#
# What is left is the two things nothing else does.
# ---------------------------------------------------------------------------
log "Samba: firewall and SELinux"
rpm -q samba-usershares >/dev/null 2>&1 \
    || warn "samba-usershares is no longer in the base; Dolphin folder sharing needs it"

# The three samba-winbind packages in the manifest are NOT part of this Samba support and
# must not be trimmed as though they were: `wine` requires samba-winbind-clients (for
# ntlm_auth), which pulls samba-winbind and samba-winbind-modules (verified with
# `repoquery --whatrequires`). They arrive with wine, and leave only with it.

# Not redundant despite the permissive default zone. Verified:
# DefaultZone=FedoraWorkstation opens TCP+UDP 1025-65535, so Steam's ports need
# nothing — but SMB uses 137/138/udp and 139/445/tcp, all below 1025.
#
# `samba-client` comes back as "ALREADY_ENABLED" in the build log: the base already has it
# in the default zone. That is expected output, not an error — the call still exits 0, and
# naming it keeps the rule from silently disappearing if the base ever drops it. Only
# `samba` is actually being added here.
firewall-offline-cmd --service=samba --service=samba-client || \
    warn "firewall-offline-cmd failed for samba"

# SELinux booleans are NOT set here. setsebool -P writes
# /var/lib/selinux/targeted/active/booleans.local, and /var is machine state: the base ships
# nothing under /var but /var/tmp, 99-cleanup.sh wipes /var back to exactly that, and bootc
# does not carry /var in the image at all. So a build-time setsebool writes a file that is
# deleted before the image is committed — while exiting 0, which is how three dead lines
# survived several audits here. (One of the three did report a failure, but only because an
# earlier %post scriptlet had already broken the policy store: semanage cannot rename
# /etc/selinux/targeted/active across overlayfs layers, "Invalid cross-device link".)
# They are set at boot instead, by system-setup.hooks.d/20-selinux-booleans.sh.

# Drop [homes]: it exports every user's home over SMB by default.
if [[ -f /etc/samba/smb.conf ]]; then
    sed -i '/^\[homes\]/,/^\[/{/^\[homes\]/d;/^\[/!d}' /etc/samba/smb.conf
    info "[homes] removed from smb.conf"
fi

# ---------------------------------------------------------------------------
# Stop applications launching a real PulseAudio daemon and fighting PipeWire.
#
# Safe to create: /usr/bin/pulseaudio is owned by the `pulseaudio` package, which is not
# installed (verified — the path does not exist in the base). A new file, not a clobbered
# one. If something ever pulls `pulseaudio` in, 99-cleanup.sh warns.
# ---------------------------------------------------------------------------
if [[ ! -L /usr/bin/pulseaudio ]]; then
    ln -sf /usr/bin/true /usr/bin/pulseaudio
    info "/usr/bin/pulseaudio -> /usr/bin/true"
fi

# ---------------------------------------------------------------------------
# Konsole on Meta+Enter as well as the stock Ctrl+Alt+T. A keybinding, not branding:
# no kdeglobals, look-and-feel package or panel layout is shipped, so stock Kinoite
# defaults survive and Vapor stays selectable rather than applied.
# ---------------------------------------------------------------------------
if [[ -f /usr/share/applications/org.kde.konsole.desktop ]]; then
    desktop-file-edit --set-key=X-KDE-Shortcuts \
        --set-value='Ctrl+Alt+T,Meta+Return' \
        /usr/share/applications/org.kde.konsole.desktop
    info "Konsole bound to Ctrl+Alt+T and Meta+Return"
fi

# ---------------------------------------------------------------------------
# /etc hygiene (Bazzite's finalize, adapted). Image-provided accounts belong in
# /usr/lib/{passwd,group}; /etc is machine-local state, and kinoite-nvidia leaves build
# residue there. Fails the build rather than shipping an image with a lost account.
# ---------------------------------------------------------------------------
log "Relocating image accounts out of /etc"
relocate_accounts() {
    local etc="$1" lib="$2" shadow="$3" keep="$4" reset="$5"
    local out line
    [[ -f "$etc" ]] || return 0
    # ANCHORED match. The pattern is a field-anchored regex ('^(root|wheel):') and not a
    # bare 'root|wheel': an unanchored version also matches any account whose NAME merely
    # contains one of those words — dockerroot, for instance — and such a line is then
    # neither kept in /etc nor relocated to /usr/lib, so it vanishes. Nothing in the base
    # trips this today (verified: only root and wheel match), but it is one new package
    # away from being a silent account loss.
    out="$(grep -vE -- "$keep" "$etc")" || true
    [[ -n "$out" ]] || return 0
    { cat "$lib" 2>/dev/null || true; printf '%s\n' "$out"; } >"${lib}.new"
    mv -f "${lib}.new" "$lib"
    while IFS= read -r line; do
        grep -qxF -- "$line" "$lib" || die "account line lost from ${lib}: ${line}"
    done <<<"$out"
    printf '%s\n' "$reset" >"$etc"
    if [[ -f "$shadow" ]]; then
        while IFS= read -r line; do
            sed -i "/^${line%%:*}:/d" "$shadow"
        done <<<"$out"
    fi
}
relocate_accounts /etc/passwd /usr/lib/passwd /etc/shadow \
    '^root:' 'root:x:0:0:root:/root:/bin/bash'
relocate_accounts /etc/group /usr/lib/group /etc/gshadow \
    '^(root|wheel):' 'root:x:0:
wheel:x:10:'
rm -f /etc/passwd- /etc/group- /etc/shadow- /etc/gshadow- \
      /etc/subuid- /etc/subgid- /etc/.pwd.lock
info "$(wc -l </usr/lib/passwd) accounts in /usr/lib/passwd"
