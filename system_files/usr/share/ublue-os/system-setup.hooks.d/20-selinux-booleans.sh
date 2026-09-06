#!/usr/bin/env bash
# PROVENANCE: mechanism is ublue-setup-services (ublue-system-setup.service runs this once
#   per version bump, same as 10-groups.sh). The content is ours: Bazzite sets no SELinux
#   booleans anywhere (verified — zero matches for setsebool or `semanage boolean` in
#   ublue-os/bazzite), so there is no upstream pattern to copy for this.
#
# WHY AT BOOT AND NOT AT BUILD TIME: setsebool -P writes the policy store under
# /var/lib/selinux/, and /var is machine state — the base ships only /var/tmp, 99-cleanup.sh
# restores /var to exactly that, and bootc does not ship /var. A build-time setsebool
# therefore persists nothing, and it exits 0 while failing to, so it looks like it worked.
source /usr/lib/ublue/setup-services/libsetup.sh

# BUMP when the boolean list below changes, or already-deployed machines will not re-run it.
version-script selinux-booleans system 1 || exit 0

set -euo pipefail

# Samba usershares. Dolphin shares arbitrary directories, which are not labelled
# samba_share_t, so smbd cannot serve them under the default policy:
#   samba_enable_home_dirs  reach paths under /var/home at all
#   samba_export_all_ro     serve files whose label is not samba_share_t
#   samba_export_all_rw     as above, writable
# Without these, a share created from Dolphin appears to work and then denies access.
# 60-system-config.sh already creates the usershares group, opens the firewall and drops
# the [homes] section; this is the remaining piece.
for boolean in samba_enable_home_dirs samba_export_all_ro samba_export_all_rw; do
    if setsebool -P "${boolean}=1"; then
        echo "SELinux boolean ${boolean}=1"
    else
        echo "warning: failed to set SELinux boolean ${boolean}"
    fi
done
