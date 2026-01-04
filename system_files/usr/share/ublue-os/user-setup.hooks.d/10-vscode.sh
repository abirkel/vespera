#!/usr/bin/env bash
# VSCode setup hook for ublue-user-setup.service

source /usr/lib/ublue/setup-services/libsetup.sh

version-script vscode user 1 || exit 1

set -x

# Setup VSCode
# Pre-install preferred VSCode Extensions
code --install-extension ms-vscode-remote.remote-containers
code --install-extension ms-vscode-remote.remote-ssh
code --install-extension ms-azuretools.vscode-containers
