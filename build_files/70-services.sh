#!/usr/bin/bash
# systemd unit state.
source "${CTX}/build_files/lib/common.sh"

log "Configuring systemd units"

# ---------------------------------------------------------------------------
# Virtualisation: modular virt*d daemons. Fedora has been moving off monolithic libvirtd
# for several releases.
#
# VERIFIED, not re-enabled. libvirt-daemon-kvm's presets already enable all nine sockets
# and virtqemud.service — `systemctl is-enabled` reports "enabled" for each straight after
# install. Calling `systemctl enable` on them was eleven no-ops. Checking instead gives the
# same protection against a preset change (the build warns) without the redundant work.
#
# virtnetworkd.service is the exception: its socket is preset-enabled but the service is
# not, so enabling it is meaningful — it brings the default NAT network up at boot rather
# than on first socket activation.
#
# CRITICAL: libvirtd.socket and virtqemud.socket both want /run/libvirt/libvirt-sock.
# Enabling both means socket activation starts the monolithic daemon and the two fight.
# Masking libvirtd makes that impossible even by accident.
# ---------------------------------------------------------------------------
for unit in virtqemud.socket virtnetworkd.socket virtstoraged.socket \
            virtnodedevd.socket virtsecretd.socket virtnwfilterd.socket \
            virtinterfaced.socket virtlogd.socket virtlockd.socket \
            virtqemud.service; do
    systemctl is-enabled "$unit" >/dev/null 2>&1 \
        || warn "${unit} is not preset-enabled by libvirt-daemon-kvm any more; enable it explicitly"
done
systemctl enable virtnetworkd.service

systemctl mask libvirtd.service libvirtd.socket \
               libvirtd-ro.socket libvirtd-admin.socket
info "modular virt*d verified; virtnetworkd enabled; monolithic libvirtd masked"

# Drivers this machine will never use; masked defensively in case a dependency ever
# drags them in.
for u in virtvboxd.service virtxend.service virtlxcd.service; do
    systemctl mask "$u" 2>/dev/null || true
done

# SELinux labelling, socket ordering and /var/log/libvirt for libvirt on ostree. Its own
# preset (54-ublue-os-libvirt-workarounds.preset) already enables it — verified, not set.
systemctl is-enabled ublue-os-libvirt-workarounds.service >/dev/null 2>&1 \
    || warn "ublue-os-libvirt-workarounds.service is no longer preset-enabled; enable it explicitly"

# ---------------------------------------------------------------------------
# Containers: rootless user socket only. Bazzite and Aurora also enable the system
# socket, which hands out a rootful API nothing here needs.
# ---------------------------------------------------------------------------
systemctl --global enable podman.socket
systemctl --global enable podman-auto-update.timer
info "podman user socket enabled (rootless); system socket deliberately not enabled"

# ---------------------------------------------------------------------------
# Drives system-setup.hooks.d / user-setup.hooks.d.
# ---------------------------------------------------------------------------
systemctl enable ublue-system-setup.service
systemctl --global enable ublue-user-setup.service

# ---------------------------------------------------------------------------
# Masks unwanted refs, then runs flatpak's own preinstall mechanism.
# ---------------------------------------------------------------------------
systemctl enable vespera-flatpak-setup.service

# ---------------------------------------------------------------------------
# Hardware.
# ---------------------------------------------------------------------------
# Auto-mounts internal partitions under /media/media-automount — useful with game
# drives on secondary disks.
systemctl enable ublue-os-media-automount.service

# Piper (Flatpak) talks to this over the system bus.
systemctl enable ratbagd.service

# Fan/pump curve daemon; the coolercontrol GUI is useless without it.
systemctl enable coolercontrold.service

# ---------------------------------------------------------------------------
# Foreground boost (Bazzite's gamemode alternative). dmemcg-booster boosts the cgroup
# of whatever the compositor reports as focused, so it needs no per-game cooperation.
# gamemode is also present for titles that call libgamemode; the two do not conflict.
#
# Three units, verified against the Terra RPMs' file lists. The Plasma one is the half
# that reports focus — without it the daemons run and boost nothing.
# ---------------------------------------------------------------------------
systemctl enable dmemcg-booster-system.service
systemctl --global enable dmemcg-booster-user.service
systemctl --global enable plasma-foreground-booster.service
info "dmemcg-booster: system + user daemons and the Plasma focus reporter enabled"

# ---------------------------------------------------------------------------
# Works around a Fedora preset bug so screen-reader speech works out of the box.
# ---------------------------------------------------------------------------
systemctl --global enable speech-dispatcher.socket 2>/dev/null \
    || warn "could not enable speech-dispatcher.socket"

# ---------------------------------------------------------------------------
# Update automation: the base's stock behaviour, asserted rather than changed.
# kinoite-main already enables rpm-ostreed-automatic.timer — which *stages* the next
# deployment, since /etc/rpm-ostreed.conf sets AutomaticUpdatePolicy=stage — plus the
# system and user flatpak timers.
#
# uupd is deliberately absent. Staging is what makes Discover's rpm-ostree backend
# pleasant ("restart to apply" rather than a long download). uupd wants to own that
# work and sets the policy back to none, so the two race for the transaction lock.
# ---------------------------------------------------------------------------
for unit in rpm-ostreed-automatic.timer flatpak-system-update.timer; do
    if systemctl is-enabled "$unit" >/dev/null 2>&1; then
        info "${unit}: enabled (inherited from base)"
    else
        warn "${unit} is not enabled; base behaviour changed"
    fi
done
grep -q '^AutomaticUpdatePolicy=stage' /etc/rpm-ostreed.conf \
    || warn "AutomaticUpdatePolicy is not 'stage'; Discover staging will not work"

# ---------------------------------------------------------------------------
# Do NOT mask fedora-atomic-desktop-appstream-cache-refresh.service. Bazzite masks it
# because Bazaar handles its own metadata; Discover needs that cache or its catalogue is
# empty. Asserted so a future change cannot break Discover silently.
# ---------------------------------------------------------------------------
if [[ -L /etc/systemd/system/fedora-atomic-desktop-appstream-cache-refresh.service ]]; then
    die "appstream cache refresh is masked; Discover needs it"
fi
info "appstream cache refresh left enabled (Discover depends on it)"
