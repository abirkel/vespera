# Vespera

[![build-ublue](https://github.com/abirkel/vespera/actions/workflows/build.yml/badge.svg)](https://github.com/abirkel/vespera/actions/workflows/build.yml)

Custom Bazzite-nvidia with Podman-focused developer tools.

## Features

### Base
- **Bazzite-nvidia** - Full gaming stack with NVIDIA drivers
- **KDE Plasma** - Desktop environment
- **Konsole** - Default terminal (not Ptyxis)

### Development Tools
- **Podman** - Container runtime (no Docker)
  - podman-compose, podman-machine, podman-bootc
  - Podman-in-Podman support (iptable_nat)
- **VSCode** - Pre-configured for Podman
  - Remote Containers extension
  - Remote SSH extension
  - Containers extension (not Docker)
- **Shells** - fish, zsh, tmux
- **Build tools** - flatpak-builder, git-credential-libsecret

### Virtualization
- **libvirt + virt-manager** - Full VM support
- **Enhanced QEMU** - VirtIO GPU/VGA, SPICE, USB redirection
- **VM tools** - virt-viewer, virt-v2v, kcli
- **TPM emulation** - swtpm workaround for modern VMs
- **Cockpit** - Web-based VM management

### Networking & File Sharing
- **WireGuard** - VPN support
- **Samba** - Windows file sharing (pre-configured)
- **iOS support** - ifuse, libimobiledevice

### System Tools
- **Cockpit suite** - Web-based system management
  - Podman containers
  - Virtual machines
  - Network configuration
  - Storage management
  - SELinux troubleshooting
- **Monitoring** - htop, powerstat, powertop
- **Backup** - rclone (cloud sync)
- **Utilities** - p7zip, wl-clipboard, kairpods

## Installation

### Rebase from Bazzite-nvidia

```bash
rpm-ostree rebase ostree-unverified-registry:ghcr.io/abirkel/vespera:latest
systemctl reboot
```

### Rebase from other Fedora Atomic

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

On first login:
- VSCode extensions install automatically
- You're added to the `libvirt` group automatically
- Podman and VMs are ready to use

## What's Different from Bazzite-DX

- ✅ **Podman-only** (no Docker)
- ✅ **Based on bazzite-nvidia** (not bazzite-deck)
- ✅ **Konsole as default** (not Ptyxis)
- ✅ **Full Cockpit suite** (8 modules)
- ✅ **TPM emulation** (swtpm workaround)
- ✅ **Enhanced VM support** (VirtIO GPU, SPICE, USB)
- ❌ **No LXC/Incus** (use Podman or VMs)
- ❌ **No Android tools** (not needed)

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
