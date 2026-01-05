#!/usr/bin/bash
set -xeuo pipefail

echo "Final cleanup..."

# Clean package manager cache
dnf5 clean all
rm -rf /var/cache/dnf5/*
rm -rf /var/log/dnf5.*

# Verify all external repos are disabled
for repo in vscode terra-mesa; do
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

# Disable any repos with missing GPG keys to prevent ISO build failures
for repo_file in /etc/yum.repos.d/*.repo; do
    if [[ -f "$repo_file" ]]; then
        # Check if repo has a gpgkey that points to a non-existent file
        if grep -q "^gpgkey=file://" "$repo_file"; then
            gpg_keys=$(grep "^gpgkey=file://" "$repo_file" | sed 's/gpgkey=file:\/\///' | tr '\n' ' ')
            for key in $gpg_keys; do
                if [[ ! -f "$key" ]]; then
                    echo "Warning: GPG key $key not found for repo $repo_file, disabling repo"
                    sed -i 's/enabled=1/enabled=0/g' "$repo_file"
                    break
                fi
            done
        fi
    fi
done

# Validate repos
echo "Checking repo status..."
dnf5 repolist --all | grep -E "(vscode|kcli|podman-bootc|kairpods|enabled)" || true

echo "Cleanup complete"
