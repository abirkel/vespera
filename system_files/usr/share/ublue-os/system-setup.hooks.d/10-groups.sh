#!/usr/bin/env bash
# PROVENANCE: mechanism is ublue-setup-services (COPR ublue-os/packages) — its
#   ublue-system-setup.service runs everything here once per version bump. Content is
#   ours: the gamemode group and the rejection of `input` are decisions made here.
#
# MEMBERSHIP is the job here. Group *creation* is handled by systemd-sysusers at every
# boot, which processes /usr/lib/sysusers.d before systemd-tmpfiles-setup (verified:
# tmpfiles has After=systemd-sysusers.service). append_group below is only a fallback
# for groups that exist in /usr/lib/group but have no sysusers.d entry — 41 of them do,
# because their package created them from %post rather than declaratively.
#
# sysusers cannot add a user to a group, so that part has to happen here.
source /usr/lib/ublue/setup-services/libsetup.sh

# BUMP THIS NUMBER whenever the behaviour below changes. version-script records it in
# the setup-checker file and exits early when it matches, so an already-deployed machine
# will never re-run an edited hook otherwise. Bumped 2 -> 3 when usershares was added to
# the membership loop, 3 -> 4 when yeetmouse was.
version-script groups system 4 || exit 0

set -euo pipefail

append_group() {
    local group="$1"
    grep -q "^${group}:" /etc/group && return 0
    if grep -q "^${group}:" /usr/lib/group; then
        grep "^${group}:" /usr/lib/group >>/etc/group
        echo "added group ${group} to /etc/group"
    else
        echo "warning: group ${group} not in /usr/lib/group; skipping"
    fi
}

# libvirt     reach the virtqemud socket without sudo
# plugdev     granted by base udev rules for Switch controllers (10-switch.rules),
#             Logitech Unifying (42-logitech-unify-permissions.rules — what ratbagd,
#             and so Piper, talks to), ZSA (50-zsa.rules), U2F (70-u2f.rules)
# gamemode    required or GameMode's renice does nothing: the base grants
#             `@gamemode - nice -10` in limits.d and the group (gid 983) exists, but
#             nothing joins it
# usershares  created by the samba-usershares package, not by us. Membership is still
#             required: /var/lib/samba/usershares is mode 1770 root:usershares, so only
#             group members can create a share from Dolphin.
# yeetmouse   yeetmouse.service chowns /sys/module/yeetmouse/parameters/* to this group;
#             membership is what lets the mouse curve be retuned without root.
#
# NOT added: `input`. Controllers use TAG+="uaccess" (119 rules in ublue's
# game-devices-udev), yeetmouse needs its own group rather than `input` (see above),
# evtest under sudo is fine — and `input` membership lets any of that user's processes
# read every keystroke.
for g in libvirt plugdev gamemode usershares yeetmouse; do
    append_group "$g"
done

mapfile -t wheel_users < <(getent group wheel | cut -d: -f4 | tr ',' '\n' | sed '/^$/d')
for user in "${wheel_users[@]}"; do
    for g in libvirt plugdev gamemode usershares yeetmouse; do
        getent group "$g" >/dev/null && usermod -aG "$g" "$user" \
            && echo "added ${user} to ${g}"
    done
done
