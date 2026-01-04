#!/usr/bin/bash
set -xeuo pipefail

echo "Fetching Aurora blocklist..."

# Create directory if it doesn't exist
mkdir -p /etc/bazaar

# Download the latest blocklist from Aurora
curl -fsSL https://raw.githubusercontent.com/get-aurora-dev/common/main/system_files/shared/etc/bazaar/blocklist.yaml \
    -o /etc/bazaar/blocklist.yaml

echo "Aurora blocklist installed successfully"
