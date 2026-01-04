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

# Disable COPR repos
for copr in karmab:kcli gmaglione:podman-bootc ledif:kairpods ublue-os:packages; do
    repo_file="/etc/yum.repos.d/copr:copr.fedorainfracloud.org:${copr//:/:}.repo"
    if [[ -f "$repo_file" ]]; then
        sed -i 's/enabled=1/enabled=0/g' "$repo_file"
    fi
done

# Validate repos
echo "Checking repo status..."
dnf5 repolist --all | grep -E "(vscode|kcli|podman-bootc|kairpods|enabled)" || true

echo "Cleanup complete"
