#!/usr/bin/bash
# dnf policy. Must run before any install.
source "${CTX}/build_files/lib/common.sh"

log "Configuring dnf"

# No Recommends. The single biggest lever on image size, and it changes dependency
# resolution for everything after it — hence step 00.
install -Dm0644 /dev/stdin /etc/dnf/libdnf5.conf.d/10-vespera.conf <<'EOF'
# Vespera: do not install weak dependencies (Recommends/Supplements).
[main]
install_weak_deps=False
EOF
# Set in both places so the build and a later `rpm-ostree install` resolve alike.
if ! grep -q '^install_weak_deps' /etc/dnf/dnf.conf 2>/dev/null; then
    printf 'install_weak_deps=False\n' >>/etc/dnf/dnf.conf
fi

# Keep metadata across layers; the Containerfile cache-mounts /var/cache/libdnf5.
dnf5 -y config-manager setopt keepcache=1

# GUARD: kinoite-main leaves the ublue-os/akmods COPR enabled at priority 85. Any
# package resolving to an `akmod-*` source package kills the build, because akmod's
# %post refuses to run as root. Found via `openrgb` -> `akmod-openrgb`.
dnf5 -y config-manager setopt \
    'copr:copr.fedorainfracloud.org:ublue-os:akmods'.exclude='akmod-*'

info "install_weak_deps=False set; akmod-* excluded from the ublue akmods COPR"
