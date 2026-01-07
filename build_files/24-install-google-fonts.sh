#!/usr/bin/bash
set -xeuo pipefail

echo "Installing Google fonts (LibreOffice/MS Office alternatives)..."

# Install Google fonts that are alternatives to MS Office fonts
# - Arimo: Alternative to Arial
# - Tinos: Alternative to Times New Roman
# - Cousine: Alternative to Courier New
# - Carlito: Alternative to Calibri
# - Caladea: Alternative to Cambria

dnf5 install -y \
    google-arimo-fonts \
    google-tinos-fonts \
    google-cousine-fonts \
    google-carlito-fonts \
    google-crosextra-caladea-fonts

echo "Google fonts installation complete"
