#!/usr/bin/bash
set -xeuo pipefail

echo "Installing VSCode from Microsoft repo..."

# Add VSCode repo (Aurora/Bazzite-DX method)
dnf5 config-manager addrepo --set=baseurl="https://packages.microsoft.com/yumrepos/vscode" --id="vscode"
dnf5 config-manager setopt vscode.enabled=0
dnf5 config-manager setopt vscode.gpgcheck=0  # FIXME: gpgcheck broken for vscode with newer rpm

# Install VSCode
dnf5 install --nogpgcheck --enable-repo="vscode" -y code

# Cleanup
dnf5 clean all
rm -rf /var/cache/dnf5/*

echo "VSCode installed"
