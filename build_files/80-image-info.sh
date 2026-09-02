#!/usr/bin/bash
# Image metadata.
#
# BRANDING POLICY: stock Kinoite branding is preserved. This is Kinoite with different
# apps and settings, not a distribution — so /usr/lib/os-release, /etc/os-release, and
# every logo, pixmap, plymouth theme and kcm-about-distrorc are left untouched.
#
# The one addition is /usr/share/ublue-os/image-info.json. Verified: kinoite-nvidia:44
# does not ship it — it is a Bazzite/Aurora convention, not a kinoite-main one — so this
# CREATES it rather than patching. Rebase helpers, ujust recipes and third-party
# updaters read it to learn what image to track; the old vespera image had a
# hand-written one claiming to be ublue-os/bazzite-nvidia-open, which is the failure
# mode this avoids.
#
# Metadata, not branding. Nothing user-visible changes.
source "${CTX}/build_files/lib/common.sh"

readonly INFO_DIR="/usr/share/ublue-os"
readonly INFO="${INFO_DIR}/image-info.json"
readonly REF="ostree-image-signed:docker://${IMAGE_REGISTRY}/${IMAGE_NAME}"

log "Writing image reference metadata (branding left stock)"

if [[ -f "${INFO}" ]]; then
    # The base grew one since this was written; merge rather than clobber.
    info "base already ships image-info.json; merging"
    info "  was: $(jq -c '{name: .["image-name"], ref: .["image-ref"]}' "${INFO}")"
    base_json="$(cat "${INFO}")"
else
    base_json='{}'
fi

version="${VERSION_TAG:-}"
if [[ -z "${version}" ]]; then
    # Never inherit a stale value from the base image's own build.
    version="$(rpm -E %fedora).$(date -u +%Y%m%d)"
fi

install -d -m0755 "${INFO_DIR}"
tmp="$(mktemp)"
jq -n \
    --argjson base    "${base_json}" \
    --arg name        "${IMAGE_NAME}" \
    --arg vendor      "${IMAGE_VENDOR}" \
    --arg ref         "${REF}" \
    --arg version     "${version}" \
    --arg fedora      "$(rpm -E %fedora)" \
    --arg base_image  "$(grep -m1 '^OSTREE_VERSION=' /usr/lib/os-release | cut -d= -f2- | tr -d "'\"")" \
    '$base + {
        "image-name":       $name,
        "image-vendor":     $vendor,
        "image-ref":        $ref,
        "image-tag":        "latest",
        "image-flavor":     "nvidia",
        "base-image-name":  "kinoite-nvidia",
        "fedora-version":   $fedora,
        "version":          $version,
        "version-pretty":   $version,
        "ostree-version":   $base_image
     }' >"${tmp}"
install -Dm0644 "${tmp}" "${INFO}"
rm -f "${tmp}"

info "wrote: $(jq -c '{name: .["image-name"], ref: .["image-ref"], version: .version}' "${INFO}")"

# ---------------------------------------------------------------------------
# Assert branding is untouched — a regression here goes unnoticed until someone opens
# the About page.
# ---------------------------------------------------------------------------
log "Verifying stock branding is intact"
declare -A expect=(
    [NAME]='"Fedora Linux"'
    [ID]='fedora'
)
for key in "${!expect[@]}"; do
    actual="$(grep -E "^${key}=" /usr/lib/os-release | head -1 | cut -d= -f2-)"
    if [[ "${actual}" != "${expect[$key]}" ]]; then
        die "os-release ${key} is ${actual}, expected ${expect[$key]} — branding must stay stock"
    fi
done
grep -qE '^VARIANT_ID=kinoite' /usr/lib/os-release \
    || warn "VARIANT_ID is not kinoite: $(grep '^VARIANT_ID=' /usr/lib/os-release || true)"
info "os-release NAME/ID/VARIANT_ID unchanged"
