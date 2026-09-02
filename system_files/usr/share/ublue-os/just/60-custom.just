# vim: set ft=make :
# PROVENANCE: conventions from ublue-os-just; recipes are ours.
#
# THE FILENAME IS LOAD-BEARING. ublue-os-just's shipped /usr/share/ublue-os/justfile
# already ends with `import? "/usr/share/ublue-os/just/60-custom.just"`, so this is
# picked up automatically. Deliberately not Bazzite's/vespera's approach of appending
# an import line to that package-owned file via sed.
#
# Conventions followed: a `# comment` directly above a recipe becomes its
# `ujust --list` description; bodies are `#!/usr/bin/bash` blocks; colour and format
# helpers come from /usr/lib/ujust/ujust.sh ($bold/$b, $normal/$n, $dim, $green,
# $yellow, $red, plus Choose / Confirm / Urllink).

# Show the state of everything this image adds on top of kinoite-nvidia
image-status:
    #!/usr/bin/bash
    source /usr/lib/ujust/ujust.sh

    echo "${bold}Image${normal}"
    if [ -r /usr/share/ublue-os/image-info.json ]; then
      jq -r '"  name    : \(.["image-name"])\n  ref     : \(.["image-ref"])"' \
        /usr/share/ublue-os/image-info.json
    fi
    echo "  booted  : $(rpm-ostree status --booted --json 2>/dev/null | jq -r '.deployments[0]."container-image-reference" // "unknown"')"

    echo
    echo "${bold}GPU${normal}"
    echo "  driver  : $(rpm -q --qf '%{VERSION}' nvidia-driver 2>/dev/null || echo absent)"
    echo "  kmod    : $(rpm -q --qf '%{VERSION}' kmod-nvidia 2>/dev/null || echo absent)"
    if [ -r /sys/module/nvidia/version ]; then
      echo "  loaded  : ${green}$(cat /sys/module/nvidia/version)${normal}"
    else
      echo "  loaded  : ${yellow}not loaded${normal}"
    fi

    echo
    echo "${bold}Virtualisation${normal} ${dim}(modular virt*d, libvirtd masked)${normal}"
    for unit in virtqemud.socket virtnetworkd.socket; do
      echo "  $unit : $(systemctl is-enabled $unit 2>/dev/null)"
    done
    echo "  libvirtd.service : $(systemctl is-enabled libvirtd.service 2>/dev/null)"
    if id -nG | tr ' ' '\n' | grep -qx libvirt; then
      echo "  libvirt group    : ${green}yes${normal}"
    else
      echo "  libvirt group    : ${yellow}no - log out and back in${normal}"
    fi

    echo
    echo "${bold}Containers${normal}"
    echo "  podman        : $(podman --version 2>/dev/null | awk '{print $3}')"
    echo "  podman.socket : $(systemctl --user is-enabled podman.socket 2>/dev/null)"
    if rpm -q docker-ce >/dev/null 2>&1; then
      echo "  docker        : ${red}present (unexpected)${normal}"
    else
      echo "  docker        : ${green}absent (intended)${normal}"
    fi

    echo
    echo "${bold}Kernel modules${normal} ${dim}(must match the running kernel exactly)${normal}"
    echo "  kernel  : $(uname -r)"
    # modinfo -k, NOT rpm -q: the two kmods use different package naming. ublue's akmods
    # build is kmod-v4l2loopback-<module version>, the COPR one is
    # kmod-yeetmouse-<kernel version>, so an rpm -q on "kmod-<m>-$(uname -r)" reported
    # v4l2loopback as missing when its .ko was present and loadable. modinfo asks the
    # running kernel's module set directly and does not care how the RPM is named.
    for m in v4l2loopback yeetmouse; do
      if modinfo -k "$(uname -r)" "${m}" >/dev/null 2>&1; then
        echo "  ${m} : ${green}built for this kernel${normal}"
      else
        echo "  ${m} : ${yellow}NOT built for this kernel${normal}"
      fi
    done

    echo
    echo "${bold}Discover backends${normal}"
    for backend in flatpak rpm-ostree fwupd kns; do
      if [ -e "/usr/lib64/qt6/plugins/discover/${backend}-backend.so" ]; then
        echo "  ${backend} : ${green}ok${normal}"
      else
        echo "  ${backend} : ${yellow}missing${normal}"
      fi
    done
    echo

# Set up LACT's root daemon, required for GPU fan curves and power limits
setup-lact:
    #!/usr/bin/bash
    source /usr/lib/ujust/ujust.sh
    set -euo pipefail

    if ! flatpak info io.github.ilya_zlobintsev.LACT >/dev/null 2>&1; then
      echo "${red}LACT is not installed.${normal}"
      echo "  flatpak install --system flathub io.github.ilya_zlobintsev.LACT"
      exit 1
    fi

    echo "${bold}Why this is needed${normal}"
    echo "LACT changes settings through a root daemon outside the Flatpak sandbox."
    echo "Without it: monitoring only - no fan curves, no power cap, no undervolt."
    echo
    CHOICE=$(Confirm "Install and enable the lactd system service now?")
    if [ "$CHOICE" -ne 0 ]; then
      echo "No changes made."
      exit 0
    fi

    flatpak run --env=LACT_UNATTENDED_SETUP=true \
      io.github.ilya_zlobintsev.LACT --version >/dev/null 2>&1 || true

    echo
    echo "${bold}One more step the Flatpak requires${normal}"
    echo "Being in the ${b}wheel${n} group is ${red}not${normal} enough - the Flatpak needs"
    echo "${b}admin_user${n} set explicitly:"
    echo
    echo "  sudo \$EDITOR /etc/lact/config.yaml"
    echo "  # under 'daemon:'   ->   admin_user: $USER"
    echo "  sudo systemctl restart lactd"
    echo
    systemctl status lactd --no-pager 2>/dev/null | head -3 || \
      echo "${yellow}lactd not running yet${normal}"

# How to mount an SMB share so it is reachable from Konsole
help-smb:
    #!/usr/bin/bash
    source /usr/lib/ujust/ujust.sh
    echo "${bold}Two approaches, both already installed.${normal}"
    echo
    echo "${b}1. Dolphin / gvfs${n} - no configuration needed"
    echo "   Mount the share in Dolphin, then reach it from Konsole under:"
    echo "     ${green}/run/user/$(id -u)/gvfs/${normal}"
    echo "   gvfs-smb and gvfs-fuse are what make that path exist."
    echo
    echo "${b}2. Kernel mount / cifs-utils${n} - persistent and faster"
    echo "   Add to /etc/fstab:"
    echo
    echo "     //server/share  /mnt/share  cifs  credentials=/etc/cifs-creds,uid=$(id -u),gid=$(id -g),_netdev,nofail  0 0"
    echo
    echo "   Create /etc/cifs-creds (${b}chmod 600${n}):"
    echo "     username=USERNAME"
    echo "     password=PASSWORD"
    echo
    echo "   Then: sudo systemctl daemon-reload && sudo mount -a"

# How to mount an iPhone or iPad over USB
help-iphone:
    #!/usr/bin/bash
    source /usr/lib/ujust/ujust.sh
    echo "${bold}Installed:${normal} usbmuxd (service), libimobiledevice-utils, ifuse, ideviceinstaller"
    echo
    echo "  1. Plug in and ${b}unlock${n} the phone, then tap Trust when prompted."
    echo "  2. Pair:          ${green}idevicepair pair${normal}"
    echo "  3. Mount:         ${green}mkdir -p ~/iphone && ifuse ~/iphone${normal}"
    echo "  4. Unmount:       ${green}fusermount -u ~/iphone${normal}"
    echo
    echo "Dolphin also shows the device once paired, via the afc KIO worker."
    echo "Diagnostics: ${b}ideviceinfo${n}, ${b}idevicesyslog${n}"

# Notes on the virtual surround / virtual channel audio building blocks
help-audio:
    #!/usr/bin/bash
    source /usr/lib/ujust/ujust.sh
    echo "${bold}Installed:${normal} pipewire-module-filter-chain-sofa, ladspa, ladspa-caps-plugins"
    echo
    echo "These are building blocks, ${b}not${n} a preconfigured surround setup."
    echo "To add a virtual 7.1 sink for headphones, drop a filter-chain config in:"
    echo "  ${green}~/.config/pipewire/pipewire.conf.d/${normal}"
    echo
    url=$(Urllink "https://docs.pipewire.org/page_module_filter_chain.html" "PipeWire filter-chain documentation")
    echo "  $url"
    echo
    echo "Reload after editing:"
    echo "  ${green}systemctl --user restart pipewire pipewire-pulse wireplumber${normal}"

# Notes on running games through gamescope with ScopeBuddy
help-gamescope:
    #!/usr/bin/bash
    source /usr/lib/ujust/ujust.sh
    echo "${bold}ScopeBuddy${normal} wraps gamescope so per-game flags live in a config file."
    echo
    echo "  ${green}scopebuddy --help${normal}"
    echo "  Steam launch options:  ${green}scopebuddy -- %command%${normal}"
    echo
    echo "Config: ${b}~/.config/scopebuddy/${n}"
    echo
    echo "${bold}Overlays${normal}"
    echo "  Native games  : host mangohud / vkBasalt / vulkan-low-latency-layer"
    echo "  Flatpak games : the Flatpak VulkanLayer extensions (installed separately)"
    echo "                  ${dim}host-side layers do not apply inside a sandbox${normal}"


# Check that Flatpak games get GPU acceleration and the MangoHud/vkBasalt overlays
check-overlays:
    #!/usr/bin/bash
    source /usr/lib/ujust/ujust.sh

    echo "${bold}Why this check exists${normal}"
    echo "Host mangohud/vkBasalt do ${b}not${n} apply inside a Flatpak sandbox, and the"
    echo "Flatpak layer extensions are pinned to a runtime version that has to match"
    echo "the runtime each app actually uses. Both are silent when wrong."
    echo

    echo "${bold}NVIDIA driver extension${normal}"
    drv=$(rpm -q --qf '%{VERSION}' nvidia-driver 2>/dev/null)
    ext="org.freedesktop.Platform.GL.nvidia-${drv//./-}"
    for e in "$ext" "${ext/GL./GL32.}"; do
      if flatpak info "$e" >/dev/null 2>&1; then
        echo "  ${green}installed${normal}  $e"
      elif flatpak remote-info flathub "$e" >/dev/null 2>&1; then
        echo "  ${yellow}available but not installed${normal}  $e"
      else
        echo "  ${red}NOT ON FLATHUB${normal}  $e"
        echo "    Flatpak apps will fall back to software rendering (llvmpipe)."
        echo "    This happens when the base bumps the driver before Flathub"
        echo "    publishes the matching extension. Wait, or pin the base digest."
      fi
    done

    echo
    echo "${bold}Vulkan layer extensions vs the runtimes that need them${normal}"
    # The only Flatpak that runs games here is Faugus; everything else is a
    # viewer or a downloader and does not need a layer.
    for app in io.github.Faugus.faugus-launcher; do
      flatpak info "$app" >/dev/null 2>&1 || { echo "  ${dim}${app} not installed${normal}"; continue; }
      rt=$(flatpak info -m "$app" 2>/dev/null | grep -m1 '^runtime=' | cut -d= -f2-)
      echo "  $app"
      echo "    runtime: ${rt}"
      want=$(flatpak remote-info --show-metadata flathub "runtime/${rt}" 2>/dev/null \
             | awk '/^\[Extension org.freedesktop.Platform.VulkanLayer\]/{f=1;next} /^\[/{f=0} f&&/version/{print;exit}' \
             | tr -d ' ' | cut -d= -f2)
      echo "    needs VulkanLayer branch: ${want:-unknown}"
      for layer in MangoHud vkBasalt; do
        # More than one branch of a layer is normal and correct: apps sit on different
        # runtimes, so 24.08 and 25.08 can both be installed. The test is therefore
        # whether the wanted branch is AMONG the installed ones — an equality test against
        # the whole list reported a false mismatch (and printed a multi-line value into the
        # middle of the message) whenever a second branch was present.
        have=$(flatpak list --columns=ref 2>/dev/null | grep -oE "VulkanLayer.${layer}/[^/]+/[^/]+$" | sed 's|.*/||' | sort -u)
        have_csv=$(echo "$have" | paste -sd, -)
        if [ -z "$have" ]; then
          echo "    ${yellow}${layer}: not installed${normal}"
        elif echo "$have" | grep -qxF "$want"; then
          echo "    ${green}${layer}: ${want} present${normal} ${dim}(installed: ${have_csv})${normal}"
        else
          echo "    ${red}${layer}: installed ${have_csv} but runtime wants ${want}${normal}"
          echo "      Fix the Branch= in /usr/share/flatpak/preinstall.d/20-vespera-vulkan-layers.preinstall"
        fi
      done
    done

    echo
    echo "${bold}Native games${normal} ${dim}(use the host copies, not the extensions)${normal}"
    for p in mangohud vkBasalt vulkan-low-latency-layer; do
      if rpm -q "$p" >/dev/null 2>&1; then echo "  ${green}$p${normal}"; else echo "  ${yellow}$p missing${normal}"; fi
    done
    for p in mangohud vkBasalt; do
      if rpm -q "${p}.i686" >/dev/null 2>&1 || rpm -q --qf '%{ARCH}\n' "$p" 2>/dev/null | grep -qx i686; then
        echo "  ${green}${p} (32-bit)${normal}"
      else
        echo "  ${yellow}${p} 32-bit missing - overlays will not show in 32-bit games${normal}"
      fi
    done
    echo
    echo "${dim}Note: vulkan-low-latency-layer has no Flatpak equivalent on Flathub,${normal}"
    echo "${dim}so it applies to native games only.${normal}"

# Check for ntsync, the kernel fast-sync primitive Wine and Proton use
check-ntsync:
    #!/usr/bin/bash
    source /usr/lib/ujust/ujust.sh

    echo "${bold}ntsync${normal} replaces esync/fsync with a kernel driver that implements"
    echo "Windows sync primitives directly. Wine 11 in this image supports it."
    echo
    if [ -e /dev/ntsync ]; then
      perms=$(stat -c '%A %U:%G' /dev/ntsync)
      echo "  device : ${green}/dev/ntsync present${normal} (${perms})"
      echo "           ${dim}the upstream driver sets mode 0666 itself, so no udev rule${normal}"
      echo "           ${dim}is needed and none is shipped${normal}"
    else
      echo "  device : ${red}/dev/ntsync MISSING${normal}"
      echo "           try: sudo modprobe ntsync"
      echo "           it should be loaded automatically by"
      echo "           /usr/lib/modules-load.d/wine-ntsync.conf"
    fi
    if [ -d /sys/module/ntsync ]; then
      echo "  module : ${green}loaded${normal}"
    else
      echo "  module : ${yellow}not loaded${normal}"
    fi
    echo "  wine   : $(rpm -q --qf '%{VERSION}' wine-core 2>/dev/null || echo absent)"
    echo
    echo "In-use check while a game is running:"
    echo "  ${green}sudo lsof /dev/ntsync${normal}"
    echo
    echo "${dim}Proton must also support it. Valve's Proton and Proton-GE builds do;${normal}"
    echo "${dim}older custom builds may need WINE_DISABLE_FAST_SYNC=0.${normal}"
