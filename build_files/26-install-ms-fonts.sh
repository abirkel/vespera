#!/usr/bin/bash
set -xeuo pipefail

echo "Installing MS Core fonts..."

CONTEXT_PATH="/ctx"
FONTS_ARCHIVE="${CONTEXT_PATH}/build_files/fonts.7z"

# Check if fonts archive exists
if [ ! -f "${FONTS_ARCHIVE}" ]; then
    echo "Warning: fonts.7z not found at ${FONTS_ARCHIVE}, skipping MS fonts installation"
    exit 0
fi

# Create temporary extraction directory
TEMP_DIR=$(mktemp -d)
cd "${TEMP_DIR}"

# Extract the archive
echo "Extracting fonts archive..."
7z x "${FONTS_ARCHIVE}" -y > /dev/null

# Install all fonts from flat archive root
echo "Installing fonts..."
FONTS_DIR="/usr/share/fonts/msfonts"
mkdir -p "${FONTS_DIR}"
find . -maxdepth 1 \( -iname "*.ttf" -o -iname "*.ttc" \) -exec cp {} "${FONTS_DIR}/" \;
chmod 644 "${FONTS_DIR}"/*
echo "Fonts installed to ${FONTS_DIR}"

# Update font cache
echo "Updating font cache..."
fc-cache -f

# Cleanup
cd /
rm -rf "${TEMP_DIR}"

echo "MS Core fonts installation complete"
