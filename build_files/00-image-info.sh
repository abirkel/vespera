#!/usr/bin/env bash
set -euxo pipefail

IMAGE_INFO="/usr/share/ublue-os/image-info.json"
IMAGE_REF="ostree-image-signed:docker://ghcr.io/$IMAGE_VENDOR/$IMAGE_NAME"

# Update image metadata
sed -i 's/"image-name": [^,]*/"image-name": "'"$IMAGE_NAME"'"/' $IMAGE_INFO
sed -i 's|"image-ref": [^,]*|"image-ref": "'"$IMAGE_REF"'"|' $IMAGE_INFO

# Update OS release
sed -i "s/^VARIANT_ID=.*/VARIANT_ID=$IMAGE_NAME/" /usr/lib/os-release

# Update KDE About page
if [[ -f /etc/xdg/kcm-about-distrorc ]]; then
    sed -i "s|^Website=.*|Website=https://github.com/$IMAGE_VENDOR/$IMAGE_NAME|" /etc/xdg/kcm-about-distrorc
    sed -i "s/^Variant=.*/Variant=Custom Bazzite-nvidia with Podman-focused developer tools/" /etc/xdg/kcm-about-distrorc
fi

echo "Image info updated"
