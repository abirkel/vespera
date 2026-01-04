#!/usr/bin/env bash
# Vespera User Flatpak Setup Hook
# Based on Aurora's flatpak user setup
# Source: https://github.com/get-aurora-dev/common/blob/main/system_files/shared/usr/share/ublue-os/user-setup.hooks.d/40-flatpak.sh

set -euo pipefail

source /usr/lib/ublue/setup-services/libsetup.sh
version-script vespera-flatpak user 1 || exit 0

# More consistent Qt/GTK themes for Flatpaks
# Gives flatpaks read-only access to GTK-4.0 config for theme consistency
flatpak override --user --filesystem=xdg-config/gtk-4.0:ro

# Fix QT Desktop Portal
# Setting QT_QPA_PLATFORMTHEME to anything other than `xdgdesktopportal`
# will break the XDG Desktop Portal inside the sandbox
# See: https://github.com/ublue-os/aurora/issues/224
flatpak override --user --unset-env=QT_QPA_PLATFORMTHEME

# WebKit override for DevPod on NVIDIA systems
# Fixes rendering issues by disabling compositing mode
flatpak override --user --env=WEBKIT_DISABLE_COMPOSITING_MODE=1 sh.loft.devpod
