#!/usr/bin/env bash
set -euo pipefail

echo "=== Configuring Vespera Flatpaks ==="

# Copy flatpak list to /etc/ublue-os/
if [[ -f /ctx/flatpaks/vespera-flatpaks.list ]]; then
    echo "Installing Vespera flatpak list..."
    install -Dm0644 /ctx/flatpaks/vespera-flatpaks.list /etc/ublue-os/vespera-flatpaks.list
else
    echo "Warning: vespera-flatpaks.list not found!"
fi

# Make vespera-flatpak-manager executable
chmod +x /usr/libexec/vespera-flatpak-manager

# Enable vespera-flatpak-manager service
echo "Enabling vespera-flatpak-manager.service..."
systemctl enable vespera-flatpak-manager.service

echo "=== Flatpak configuration complete ==="
