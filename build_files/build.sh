#!/usr/bin/bash
# Runs every numbered script in order. The ordering is load-bearing:
#   00  dnf policy (install_weak_deps) must land BEFORE any install
#   10  Fedora packages in bulk, no third-party repo enabled
#   20  third-party repos, each scoped to one transaction
#   30  kmods, which must match the base image's exact kernel
#   40  fonts
#   50  flatpak declarations
#   60  system configuration
#   70  systemd unit state
#   80  image metadata (minimal; branding stays stock)
#   99  cleanup + lint prep
set -Eeuo pipefail

export CTX=/ctx
# shellcheck source=lib/common.sh
source "${CTX}/build_files/lib/common.sh"

log "Vespera build starting"
info "base kernel : $(kernel_version)"
info "image       : ${IMAGE_VENDOR:-?}/${IMAGE_NAME:-?}"

for script in "${CTX}"/build_files/[0-9][0-9]-*.sh; do
    [[ -f "$script" ]] || continue
    name="$(basename "$script")"
    group_start "${name}"
    bash "$script"
    group_end
done

if [[ -s "${WARNINGS_FILE}" ]]; then
    printf '\n\033[1;33m===== BUILD COMPLETED WITH WARNINGS =====\033[0m\n'
    cat "${WARNINGS_FILE}"
    printf '\033[1;33m=========================================\033[0m\n\n'
else
    log "Build complete, no warnings"
fi
