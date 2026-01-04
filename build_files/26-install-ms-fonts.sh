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

# Install mscore fonts
if [ -d "mscore" ]; then
    echo "Installing MS Core fonts..."
    MSCORE_DIR="/usr/share/fonts/mscore"
    mkdir -p "${MSCORE_DIR}"
    cp mscore/*.{ttf,ttc,TTF,TTC} "${MSCORE_DIR}/" 2>/dev/null || true
    chmod 644 "${MSCORE_DIR}"/* 2>/dev/null || true
    echo "MS Core fonts installed to ${MSCORE_DIR}"
fi

# Install additional fonts
if [ -d "additional" ]; then
    echo "Installing additional fonts..."
    ADDITIONAL_DIR="/usr/share/fonts/additional"
    mkdir -p "${ADDITIONAL_DIR}"
    cp additional/*.{ttf,ttc,TTF,TTC} "${ADDITIONAL_DIR}/" 2>/dev/null || true
    chmod 644 "${ADDITIONAL_DIR}"/* 2>/dev/null || true
    echo "Additional fonts installed to ${ADDITIONAL_DIR}"
fi

# Update font cache
echo "Updating font cache..."
fc-cache -f

# Cleanup
cd /
rm -rf "${TEMP_DIR}"

echo "MS Core fonts installation complete"
