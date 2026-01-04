# Vespera

[![build-ublue](https://github.com/abirkel/vespera/actions/workflows/build.yml/badge.svg)](https://github.com/abirkel/vespera/actions/workflows/build.yml)

Custom Bazzite-nvidia with Podman-focused developer tools.

## What We Changed

### Packages Added
- **Containers**: podman-compose, podman-machine, podman-bootc, podman-tui
- **Virtualization**: qemu-kvm, libvirt, virt-manager, virt-viewer, virt-v2v, kcli, edk2-ovmf
- **QEMU enhancements**: VirtIO GPU/VGA, SPICE, USB redirection
- **Development**: VSCode, flatpak-builder, git-credential-libsecret
- **Shells**: fish, zsh, tmux
- **Networking**: wireguard-tools, samba (winbind stack)
- **iOS support**: ifuse, libimobiledevice, usbmuxd, ideviceinstaller
- **System tools**: htop, powerstat, powertop, rclone, p7zip, wl-clipboard
- **Cockpit modules**: machines, networkmanager, ostree, podman, selinux, storaged, system
- **KDE**: plasma-firewall, konsole
- **Input**: yeetmouse (kmod + userspace)
- **Utilities**: kairpods, ublue-os-libvirt-workarounds, ublue-setup-services

### System Configuration
- **Konsole restored** as default terminal (Ctrl+Alt+T, taskbar)
- **Samba pre-configured** for file sharing (Aurora method)
- **iptable_nat module** loaded for podman-in-podman
- **Writable /opt** via symlink to /var/opt (Aurora method)
- **ACQ100S sleep script** for suspend/resume handling
- **TPM emulation** via swtpm-workaround service
- **Firefox config** with Vespera defaults
- **VSCode profile** auto-applies settings on first launch

### Services Enabled
- podman.socket, libvirtd.socket, virtlogd.socket
- ublue-os-libvirt-workarounds.service, swtpm-workaround.service
- ublue-system-setup.service, ublue-user-setup.service (global)
- vespera-flatpak-manager.service

### User Setup Hooks
- **Auto-add to libvirt group** on first login
- **VSCode extensions** auto-install (ms-vscode-remote.remote-containers, ms-vscode-remote.remote-ssh, ms-azuretools.vscode-docker)
- **Flatpak manager** installs curated app list on first boot

### Just Commands
- dx-status, dx-test-podman, dx-test-vm, dx-install-extras, dx-vms
- install-vespera-flatpaks, list-vespera-flatpaks

### Fonts
- Microsoft TrueType fonts (Arial, Times New Roman, etc.)
- Nerd Fonts (JetBrainsMono, FiraCode, Hack, etc.)

### Flatpaks
Curated list includes Firefox, KDE apps (Krita, Okular, Gwenview), gaming tools (Bottles, ProtonPlus, Protontricks), dev tools (Podman Desktop, Kontainer), and utilities (Flatseal, Warehouse, Piper, LocalSend, Vesktop)

## Installation

### Signed Images (Recommended)

```bash
# Add signing key
sudo mkdir -p /etc/pki/containers
sudo curl -o /etc/pki/containers/vespera.pub https://raw.githubusercontent.com/abirkel/vespera/main/cosign.pub

# Rebase to signed image
rpm-ostree rebase ostree-image-signed:docker://ghcr.io/abirkel/vespera:latest
systemctl reboot
```

### Unsigned Images

```bash
rpm-ostree rebase ostree-unverified-registry:ghcr.io/abirkel/vespera:latest
systemctl reboot
```

## Usage

### Just Commands

```bash
# Check environment status
ujust dx-status

# Test Podman
ujust dx-test-podman

# Test VMs
ujust dx-test-vm

# Install extra dev tools (lazygit, lazydocker, dive)
ujust dx-install-extras

# Open virt-manager
ujust dx-vms
```

### First Boot

On first login, automatic setup runs:
- VSCode extensions install
- User added to libvirt group
- Flatpaks install from curated list
- Podman and VMs ready to use

## Building Locally

```bash
podman build -t vespera:latest .
```

## Verification

After reboot, verify:

```bash
# Check groups
groups | grep libvirt

# Test Podman
podman run --rm hello-world

# Test VMs
virsh list --all

# Check VSCode extensions
code --list-extensions

# Verify /opt is writable
ls -la /opt  # Should be symlink to /var/opt
```

## Credits

Based on:
- [Bazzite](https://github.com/ublue-os/bazzite) by Universal Blue
- [Aurora](https://github.com/ublue-os/aurora) by Universal Blue
- [image-template](https://github.com/ublue-os/image-template) by Universal Blue

## License

See [LICENSE](LICENSE)
