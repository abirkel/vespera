#!/usr/bin/env bash
# Group setup hook for ublue-system-setup.service

source /usr/lib/ublue/setup-services/libsetup.sh

version-script groups system 1 || exit 1

set -x

# Function to append a group entry to /etc/group
append_group() {
  local group_name="$1"
  if ! grep -q "^$group_name:" /etc/group; then
    echo "Appending $group_name to /etc/group"
    grep "^$group_name:" /usr/lib/group | tee -a /etc/group >/dev/null
  fi
}

# Setup libvirt group
append_group libvirt

# Add all wheel users to libvirt group
wheelarray=($(getent group wheel | cut -d ":" -f 4 | tr ',' '\n'))
for user in $wheelarray; do
  usermod -aG libvirt $user
done
