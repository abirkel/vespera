#!/usr/bin/env bash
# Vespera User Flatpak Setup Hook
# Based on Aurora's flatpak user setup
# Source: https://github.com/get-aurora-dev/common/blob/main/system_files/shared/usr/share/ublue-os/user-setup.hooks.d/40-flatpak.sh

set -euo pipefail

# Simple version tracking (Aurora uses libsetup.sh, we use a simpler approach)
VER=1
VER_FILE="${XDG_DATA_HOME:-${HOME}/.local/share}/vespera/flatpak_hook_version"
VER_RAN=$(cat "$VER_FILE" 2>/dev/null || echo "0")

if [[ "$VER" == "$VER_RAN" ]]; then
    echo "Vespera flatpak hook v$VER has already run. Exiting..."
    exit 0
fi

echo "Running Vespera flatpak user setup hook v$VER..."

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

# Save version to prevent re-running
mkdir -p "$(dirname "$VER_FILE")"
echo "$VER" > "$VER_FILE"

echo "Vespera flatpak user hooks applied successfully"
