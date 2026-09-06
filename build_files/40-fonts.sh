#!/usr/bin/bash
# Fonts fetched from outside the package manager.
source "${CTX}/build_files/lib/common.sh"

# ---------------------------------------------------------------------------
# Nerd Fonts — three patched families only.
#
# PINNED on purpose. `releases/latest/download` makes the same commit produce different
# images over time — the reproducibility bug vespera's script 25 had. Renovate bumps
# NERD_FONTS_VERSION.
#
# Deliberately NOT the `nerd-fonts` COPR mega-package: the full collection is enormous
# for the sake of one or two families.
# ---------------------------------------------------------------------------
readonly NERD_FONTS_VERSION="v3.5.1"
readonly NERD_FONTS=( CodeNewRoman CascadiaCode CascadiaMono )
readonly NF_DIR="/usr/share/fonts/nerd-fonts"

log "Nerd Fonts ${NERD_FONTS_VERSION}: ${NERD_FONTS[*]}"
install -d -m0755 "${NF_DIR}"

for font in "${NERD_FONTS[@]}"; do
    tmp="$(mktemp -d)"
    if fetch -o "${tmp}/${font}.tar.xz" \
        "https://github.com/ryanoasis/nerd-fonts/releases/download/${NERD_FONTS_VERSION}/${font}.tar.xz"
    then
        # Stage, then copy only font files. The tarballs are flat today, but this
        # survives that changing and avoids chmod 0644 landing on a directory.
        stage="${tmp}/x"; install -d "${stage}"
        tar -xJf "${tmp}/${font}.tar.xz" -C "${stage}"
        find "${stage}" -type f \( -iname '*.ttf' -o -iname '*.otf' \) \
            -exec install -m0644 -t "${NF_DIR}" {} +
        info "installed ${font}"
    else
        warn "Nerd Font ${font}: download failed; skipped"
    fi
    rm -rf "${tmp}"
done

# ---------------------------------------------------------------------------
# Microsoft core fonts.
#
# LICENSING: the "Core fonts for the Web" terms permitted redistribution only as the
# original unmodified self-extracting archives, so no font blob is vendored here.
# (vespera committed an 86 MB fonts.7z, which every clone and CI run had to transfer and
# which republished the fonts from a public image.) The original cabinets are fetched at
# build time and extracted with cabextract, as the mscorefonts installer does.
#
# The metric-compatible Google fonts in 10-packages-fedora.sh already make Office
# documents lay out correctly; this is only for pixel-exact rendering.
# ENABLE_MSFONTS=0 skips it.
# ---------------------------------------------------------------------------
if [[ "${ENABLE_MSFONTS:-1}" != "1" ]]; then
    info "MS core fonts: disabled by ENABLE_MSFONTS=0"
else
    log "Microsoft core fonts (fetched, not vendored)"
    readonly MS_DIR="/usr/share/fonts/msttcore"
    readonly MS_BASE="https://downloads.sourceforge.net/corefonts"
    readonly MS_CABS=(
        andale32.exe arial32.exe arialb32.exe comic32.exe courie32.exe
        georgi32.exe impact32.exe times32.exe trebuc32.exe verdan32.exe
        webdin32.exe
    )
    tmp="$(mktemp -d)"
    ok=0
    for cab in "${MS_CABS[@]}"; do
        if fetch -o "${tmp}/${cab}" "${MS_BASE}/${cab}"; then
            cabextract -L -q -d "${tmp}/out" "${tmp}/${cab}" && ok=$(( ok + 1 ))
        else
            warn "MS core fonts: ${cab} download failed"
        fi
    done
    if (( ok > 0 )); then
        install -d -m0755 "${MS_DIR}"
        find "${tmp}/out" -type f \( -iname '*.ttf' -o -iname '*.ttc' \) \
            -exec install -m0644 -t "${MS_DIR}" {} +
        info "extracted ${ok}/${#MS_CABS[@]} cabinets"
    else
        warn "MS core fonts: nothing extracted; skipped"
    fi
    rm -rf "${tmp}"
fi

# One cache rebuild, not one per font.
log "Rebuilding font cache"
fc-cache -f >/dev/null
