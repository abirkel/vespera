# vim: set ft=make :

# Show developer environment status
dx-status:
    #!/usr/bin/bash
    echo "=== Vespera Environment Status ==="
    echo ""
    echo "Podman:"
    podman --version
    systemctl status podman.socket --no-pager | head -3
    echo ""
    echo "Libvirt:"
    virsh --version 2>/dev/null || echo "Not running"
    systemctl status libvirtd.socket --no-pager | head -3
    echo ""
    echo "VSCode:"
    code --version 2>/dev/null || echo "Not found"
    echo ""
    echo "User Groups:"
    groups | grep -E "libvirt" && echo "✓ In libvirt group" || echo "✗ Not in libvirt group"

# Test Podman
dx-test-podman:
    #!/usr/bin/bash
    echo "Testing Podman..."
    podman run --rm hello-world
    echo "✓ Podman working!"

# Test VM creation
dx-test-vm:
    #!/usr/bin/bash
    echo "Testing libvirt..."
    virsh list --all
    echo "✓ Libvirt working!"

# Install additional dev tools via brew
dx-install-extras:
    #!/usr/bin/bash
    echo "Installing additional dev tools via Homebrew..."
    brew install lazygit lazydocker dive
    echo "✓ Done!"

# Open virt-manager
dx-vms:
    #!/usr/bin/bash
    virt-manager &
