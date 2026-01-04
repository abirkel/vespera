#!/usr/bin/bash
set -xeuo pipefail

echo "Final cleanup..."

# Clean package manager cache
dnf5 clean all
rm -rf /var/cache/dnf5/*
rm -rf /var/log/dnf5.*

# Verify all external repos are disabled
for repo in vscode; do
    if [[ -f /etc/yum.repos.d/${repo}.repo ]]; then
        sed -i 's/enabled=1/enabled=0/g' /etc/yum.repos.d/${repo}.repo
    fi
done

# Disable COPR repos (Aurora method - use glob pattern)
for i in /etc/yum.repos.d/_copr:*.repo; do
    if [[ -f "$i" ]]; then
        sed -i 's/enabled=1/enabled=0/g' "$i"
    fi
done

# Validate repos
echo "Checking repo status..."
dnf5 repolist --all | grep -E "(vscode|kcli|podman-bootc|kairpods|enabled)" || true

echo "Cleanup complete"
