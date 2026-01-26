#!/usr/bin/bash
set -xeuo pipefail

echo "Enabling services..."

# Enable Podman socket
systemctl enable podman.socket

# Enable libvirt services
systemctl enable libvirtd.socket
systemctl enable virtlogd.socket

# Enable libvirt and swtpm workarounds (from Aurora-DX)
systemctl enable ublue-os-libvirt-workarounds.service
systemctl enable swtpm-workaround.service

# Enable ublue setup services (from Aurora-DX/Bazzite-DX)
systemctl enable ublue-system-setup.service
systemctl --global enable ublue-user-setup.service

# Enable Homebrew setup service (from Bazzite)
systemctl enable brew-setup.service

# Enable coolercontrol daemon (required for coolercontrol to function)
systemctl enable coolercontrold.service

echo "Services enabled"
