#!/usr/bin/bash
set -xeuo pipefail

echo "Installing Nerd Fonts..."

# Create fonts directory
mkdir -p /usr/share/fonts/nerd-fonts

# Download and install Nerd Fonts
FONTS=(
    "CodeNewRoman"
    "CascadiaCode"
    "CascadiaMono"
    "AurulentSansMono"
)

for font in "${FONTS[@]}"; do
    echo "Downloading ${font}..."
    curl -fsSL "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/${font}.tar.xz" \
        -o "/tmp/${font}.tar.xz"
    
    echo "Installing ${font}..."
    tar -xJf "/tmp/${font}.tar.xz" -C /usr/share/fonts/nerd-fonts/
    rm "/tmp/${font}.tar.xz"
done

# Set permissions
chmod 644 /usr/share/fonts/nerd-fonts/*

# Update font cache
fc-cache -f

echo "Nerd Fonts installation complete"
