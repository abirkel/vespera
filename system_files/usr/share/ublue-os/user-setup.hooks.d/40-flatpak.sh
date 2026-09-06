#!/usr/bin/env bash
# PROVENANCE: mechanism is ublue-setup-services (ublue-user-setup runs this per user);
#   content adapted from Aurora's equivalent hook.
source /usr/lib/ublue/setup-services/libsetup.sh

version-script vespera-flatpak user 1 || exit 0

set -euo pipefail

# Let Flatpaks read the host GTK4 config so GTK apps pick up Breeze consistently.
flatpak override --user --filesystem=xdg-config/gtk-4.0:ro

# Setting QT_QPA_PLATFORMTHEME to anything but xdgdesktopportal breaks the portal
# inside a sandbox, so drop whatever the host exported.
# https://github.com/ublue-os/aurora/issues/224
flatpak override --user --unset-env=QT_QPA_PLATFORMTHEME

echo "Flatpak user overrides applied"
