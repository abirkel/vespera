#!/usr/bin/bash
set -xeuo pipefail

echo "Installing core development packages..."

# Helper function for isolated COPR installation (from Aurora)
copr_install_isolated() {
    local copr_repo="$1"
    shift
    local packages=("$@")
    
    if [[ ${#packages[@]} -eq 0 ]]; then
        echo "ERROR: No packages specified for copr_install_isolated"
        return 1
    fi

    repo_id="copr:copr.fedorainfracloud.org:${copr_repo//\//:}"

    echo "Installing ${packages[*]} from COPR $copr_repo (isolated)"

    dnf5 -y copr enable "$copr_repo"
    dnf5 -y copr disable "$copr_repo"
    dnf5 -y install --enablerepo="$repo_id" "${packages[@]}"

    echo "Installed ${packages[*]} from $copr_repo"
}

# Main package installation
dnf5 install -y \
    podman-compose \
    podman-machine \
    podman-tui \
    qemu-kvm \
    qemu-img \
    qemu-system-x86-core \
    qemu-char-spice \
    qemu-device-display-virtio-gpu \
    qemu-device-display-virtio-vga \
    qemu-device-usb-redirect \
    libvirt \
    libvirt-nss \
    virt-manager \
    virt-viewer \
    virt-v2v \
    edk2-ovmf \
    flatpak-builder \
    git-credential-libsecret \
    fish \
    zsh \
    tmux \
    htop \
    wireguard-tools \
    samba-winbind \
    samba-winbind-clients \
    samba-winbind-modules \
    ifuse \
    libimobiledevice \
    libimobiledevice-utils \
    usbmuxd \
    ideviceinstaller \
    powerstat \
    powertop \
    rclone \
    p7zip \
    p7zip-plugins \
    wl-clipboard \
    cockpit-bridge \
    cockpit-machines \
    cockpit-networkmanager \
    cockpit-ostree \
    cockpit-podman \
    cockpit-selinux \
    cockpit-storaged \
    cockpit-system \
    plasma-firewall \
    konsole \
    levien-inconsolata-fonts \
    google-roboto-mono-fonts \
    google-droid-sans-mono-fonts

# Add abirkel-stable repository
echo "Adding abirkel-stable repository..."
dnf5 config-manager addrepo --from-repofile=https://abirkel.github.io/rpm-repo/abirkel-stable.repo

# Install packages from abirkel-stable repo
echo "Installing packages from abirkel-stable..."
dnf5 install -y \
    kmod-yeetmouse \
    yeetmouse \
    pia-nm

# Install from COPRs using isolated enablement (Aurora method)
echo "Installing COPR packages..."

copr_install_isolated "karmab/kcli" "kcli"
copr_install_isolated "gmaglione/podman-bootc" "podman-bootc"
copr_install_isolated "ledif/kairpods" "kairpods"
copr_install_isolated "ublue-os/packages" "ublue-os-libvirt-workarounds" "ublue-setup-services"

# Install liquidctl and coolercontrol from Terra repository
echo "Installing liquidctl and coolercontrol from Terra repository..."

# Enable Terra repository (it's disabled by default in base Bazzite image)
TERRA_REPO="/etc/yum.repos.d/terra.repo"
if [ -f "$TERRA_REPO" ]; then
    echo "Enabling Terra repository..."
    sed -i 's/enabled=0/enabled=1/g' "$TERRA_REPO"
else
    echo "Warning: Terra repository not found at $TERRA_REPO"
fi

dnf5 install -y \
    liquidctl \
    coolercontrol

# Note: Terra repo will be disabled again in 99-cleanup.sh to match Bazzite's default state

# Cleanup
dnf5 clean all
rm -rf /var/cache/dnf5/*

echo "Package installation complete"
