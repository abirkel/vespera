#!/usr/bin/bash
# Fedora packages, installed first and in bulk with no third-party repo enabled, so
# no COPR or Terra build can shadow a Fedora package.
source "${CTX}/build_files/lib/common.sh"

log "Installing Fedora packages"

# ---------------------------------------------------------------------------
# ALREADY IN THE BASE — asserted, not reinstalled. Re-requesting is a dnf no-op, but
# it makes this file misrepresent what the image adds and hides the day the base drops
# one. Verified against kinoite-nvidia:44.
#
#   7zip       owns /usr/bin/7z and Provides p7zip-plugins, which is what ark needs.
#              `p7zip` and `p7zip-plugins` no longer exist in Fedora 44 — requesting
#              `p7zip` fails the transaction.
#   gamemode   D-Bus activated, so nothing to enable — but see the `gamemode` group in
#              10-groups.sh, without which its renice does nothing.
#   toolbox, distrobox   no container-workflow gap; only podman-compose and podman-tui
#              are missing.
#   libva-nvidia-driver, vulkan-tools, clinfo, jq, lsof, kate, libbluray,
#   pkgconf-pkg-config, perl-interpreter, gawk
# ---------------------------------------------------------------------------
for p in 7zip gamemode libva-nvidia-driver vulkan-tools clinfo jq lsof kate \
         libbluray pkgconf-pkg-config toolbox distrobox; do
    rpm -q "$p" >/dev/null 2>&1 || warn "expected '${p}' in the base image but it is missing; add it to a list below"
done

# ---------------------------------------------------------------------------
# Gaming.
#
# ONE TRANSACTION: the .i686 packages are Vulkan layers and audio shims that must
# exist in both arches, because a 32-bit game process loads the 32-bit layer. Keeping
# them with their 64-bit halves resolves multilib once against a consistent view.
#
# 32-BIT WINE IS NOT NEEDED — a change from older advice. Fedora 44's Wine 11 is
# new-WoW64 (/usr/lib64/wine-wow64/wine/{i386-windows,x86_64-unix,x86_64-windows}), so
# 32-bit Windows binaries run on a 64-bit host with no 32-bit ELF libraries. Verified:
# `wine` on x86_64 pulls zero i686 packages and there is no /usr/lib/wine tree.
# `wine-core.i686` is the legacy path, 653 MB, and installing it is what used to
# trigger the wine-dxgi(x86-32) alternatives conflict.
# ---------------------------------------------------------------------------
GAMING=(
    gamescope
    mangohud mangohud.i686
    vkBasalt vkBasalt.i686
    libFAudio libFAudio.i686
    wine winetricks
    protontricks            # native, because Steam here is native (see README)
    goverlay
    libxcrypt-compat        # legacy libcrypt.so.1 for old game binaries
    python3-icoextract      # real icons for Wine/Proton shortcuts
)

# ---------------------------------------------------------------------------
# Virtualisation. Fedora's current recommendation is the modular virt*d daemons, not
# monolithic libvirtd; libvirt-daemon-kvm pulls the KVM driver set instead of the
# Xen/VirtualBox/LXC ones. bcvk replaces podman-bootc — same job without the full
# `qemu` metapackage and its 34 cross-arch emulators.
# ---------------------------------------------------------------------------
VIRT=(
    libvirt-daemon-kvm
    virt-install
    virtiofsd
    swtpm-tools
    bcvk
    qemu-kvm qemu-img
    qemu-char-spice
    qemu-device-usb-redirect
    qemu-device-display-virtio-gpu
    qemu-device-display-virtio-gpu-gl
    qemu-device-display-virtio-vga
    udica
)

# ---------------------------------------------------------------------------
# KDE. plasma-firewall-firewalld is explicit because install_weak_deps=False means
# Recommends are not pulled.
#
# plasma-discover-rpm-ostree is the important one. Verified: stock
# fedora-ostree-desktops/kinoite:44 ships it, but ublue's kinoite-main removes it —
# it is under `all.exclude.kinoite` in ublue-os/main's packages.json. Putting it back
# restores Discover's "System Update" entry driving rpm-ostree, which is the point of
# building on Kinoite rather than Bazzite. One package, 256 KiB, no dependencies.
#
# Caveat: that backend can also *layer* packages, and anything layered diverges from
# the image and is discarded on rebase. Packages belong here, not in Discover.
# ---------------------------------------------------------------------------
KDE=(
    plasma-discover-rpm-ostree
    plasma-firewall plasma-firewall-firewalld
    plasma-union                # new unified Plasma Qt style
    plasma-oxygen               # legacy Oxygen style, opt-in in System Settings
    oxygen-icon-theme
    ksystemlog
)

# ---------------------------------------------------------------------------
# iPhone over USB. libimobiledevice, its utils and usbmuxd (plus udev rules and unit)
# are already in the base; ifuse and ideviceinstaller are the missing halves.
# ---------------------------------------------------------------------------
IDEVICE=(
    ifuse
    ideviceinstaller
)

# ---------------------------------------------------------------------------
# Network filesystems. gvfs-smb + gvfs-fuse is what makes a share mounted in Dolphin
# visible to Konsole under /run/user/$UID/gvfs/. cifs-utils is already in the base for
# real kernel mounts via /etc/fstab.
# ---------------------------------------------------------------------------
NETFS=(
    gvfs gvfs-client gvfs-fuse gvfs-smb
)

# ---------------------------------------------------------------------------
# Audio. The SOFA filter-chain module is the engine behind virtual 7.1 surround over
# stereo headphones; the LADSPA/CAPS plugins are what surround recipes build on.
# ---------------------------------------------------------------------------
AUDIO=(
    pipewire-module-filter-chain-sofa
    ladspa
    ladspa-caps-plugins
)

# ---------------------------------------------------------------------------
# Shells and CLI. The two zsh plugins give it fish's headline features; /etc/skel/
# .zshrc wires them up.
# ---------------------------------------------------------------------------
CLI=(
    fish
    zsh zsh-autosuggestions zsh-syntax-highlighting
    gh
    duf pv evtest
    setools-console
    rclone
    fastfetch glow gum
    strace
)
# 7-Zip: see the assertion block at the top. Nothing to install.
rpm -q 7zip >/dev/null 2>&1 || warn "7zip is no longer in the base; add it to CLI"

# ---------------------------------------------------------------------------
# Containers and light development. Not included: full `git` (base has git-core; full
# git drags in a Perl tail), git-lfs, kernel-devel (kmods are prebuilt), Docker, incus,
# VS Code.
# ---------------------------------------------------------------------------
DEV=(
    podman-compose
    podman-tui
    flatpak-builder
    git-credential-libsecret
    gcc gcc-c++ make cmake
)

# ---------------------------------------------------------------------------
# Fonts. Metric-compatible substitutes for the MS Office core set — this is what
# makes Office documents lay out correctly, with no licensing question.
# ---------------------------------------------------------------------------
FONTS=(
    google-arimo-fonts              # Arial
    google-tinos-fonts              # Times New Roman
    google-cousine-fonts            # Courier New
    google-carlito-fonts            # Calibri
    google-crosextra-caladea-fonts  # Cambria
    fira-code-fonts
)

# ---------------------------------------------------------------------------
# OCR for Spectacle. Japanese only; `eng` ships with tesseract.
# ---------------------------------------------------------------------------
OCR=(
    tesseract
    tesseract-langpack-jpn
    tesseract-langpack-jpn_vert
)

# Blu-ray. The decryption shim (makemkv/libmmbd) comes from negativo17 next.
BLURAY=( libbluray-utils )

# Needed by 40-fonts.sh to extract the MS core font cabinets.
FONT_TOOLS=( cabextract )

dnf5 -y install \
    "${GAMING[@]}" \
    "${VIRT[@]}" \
    "${KDE[@]}" \
    "${IDEVICE[@]}" \
    "${NETFS[@]}" \
    "${AUDIO[@]}" \
    "${CLI[@]}" \
    "${DEV[@]}" \
    "${FONTS[@]}" \
    "${OCR[@]}" \
    "${BLURAY[@]}" \
    "${FONT_TOOLS[@]}"

info "Fedora package set installed"

# Steam and full openh264 come from negativo17, shipped disabled in the base.
log "Installing Steam + openh264 from negativo17"
repo_install 'fedora-multimedia' \
    steam \
    openh264 openh264.i686

# Hide TUI/utility launchers from the app grid.
for d in nvtop btop yad-icon-browser; do
    [[ -f "/usr/share/applications/${d}.desktop" ]] &&
        desktop-file-edit --set-key=Hidden --set-value=true \
            "/usr/share/applications/${d}.desktop" || true
done
