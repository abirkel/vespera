#!/usr/bin/bash
set -xeuo pipefail

echo "Installing additional Nerd Fonts (Hack and Cousine)..."

NERD_FONTS_VERSION="v3.4.0"
FONTS_DIR="/usr/share/fonts/nerd-fonts-extra"
TEMP_DIR="/tmp/nerd-fonts-install"

# Create directories
mkdir -p "${FONTS_DIR}"
mkdir -p "${TEMP_DIR}"

# Download and install Hack Nerd Font
echo "Downloading Hack Nerd Font..."
curl -fsSL "https://github.com/ryanoasis/nerd-fonts/releases/download/${NERD_FONTS_VERSION}/Hack.zip" \
    -o "${TEMP_DIR}/Hack.zip"

echo "Installing Hack Nerd Font..."
unzip -q "${TEMP_DIR}/Hack.zip" -d "${TEMP_DIR}/Hack"
find "${TEMP_DIR}/Hack" -name "*.ttf" -exec cp {} "${FONTS_DIR}/" \;

# Download and install Cousine Nerd Font
echo "Downloading Cousine Nerd Font..."
curl -fsSL "https://github.com/ryanoasis/nerd-fonts/releases/download/${NERD_FONTS_VERSION}/Cousine.zip" \
    -o "${TEMP_DIR}/Cousine.zip"

echo "Installing Cousine Nerd Font..."
unzip -q "${TEMP_DIR}/Cousine.zip" -d "${TEMP_DIR}/Cousine"
find "${TEMP_DIR}/Cousine" -name "*.ttf" -exec cp {} "${FONTS_DIR}/" \;

# Download and install Inconsolata Nerd Font
echo "Downloading Inconsolata Nerd Font..."
curl -fsSL "https://github.com/ryanoasis/nerd-fonts/releases/download/${NERD_FONTS_VERSION}/Inconsolata.zip" \
    -o "${TEMP_DIR}/Inconsolata.zip"

echo "Installing Inconsolata Nerd Font..."
unzip -q "${TEMP_DIR}/Inconsolata.zip" -d "${TEMP_DIR}/Inconsolata"
find "${TEMP_DIR}/Inconsolata" -name "*.ttf" -exec cp {} "${FONTS_DIR}/" \;

# Download and install RobotoMono Nerd Font
echo "Downloading RobotoMono Nerd Font..."
curl -fsSL "https://github.com/ryanoasis/nerd-fonts/releases/download/${NERD_FONTS_VERSION}/RobotoMono.zip" \
    -o "${TEMP_DIR}/RobotoMono.zip"

echo "Installing RobotoMono Nerd Font..."
unzip -q "${TEMP_DIR}/RobotoMono.zip" -d "${TEMP_DIR}/RobotoMono"
find "${TEMP_DIR}/RobotoMono" -name "*.ttf" -exec cp {} "${FONTS_DIR}/" \;

# Download and install DroidSansM Nerd Font
echo "Downloading DroidSansM Nerd Font..."
curl -fsSL "https://github.com/ryanoasis/nerd-fonts/releases/download/${NERD_FONTS_VERSION}/DroidSansMono.zip" \
    -o "${TEMP_DIR}/DroidSansMono.zip"

echo "Installing DroidSansM Nerd Font..."
unzip -q "${TEMP_DIR}/DroidSansMono.zip" -d "${TEMP_DIR}/DroidSansMono"
find "${TEMP_DIR}/DroidSansMono" -name "*.ttf" -exec cp {} "${FONTS_DIR}/" \;

# Update font cache
echo "Updating font cache..."
fc-cache -f "${FONTS_DIR}"

# Cleanup
rm -rf "${TEMP_DIR}"

echo "Additional Nerd Fonts installation complete"
