# vespera

A custom [bootc](https://bootc-dev.github.io/bootc/) image: Fedora Kinoite with
NVIDIA, gaming and light development tooling, built on
`ghcr.io/ublue-os/kinoite-nvidia`.


```
ghcr.io/abirkel/vespera:latest
```
[![build-ublue](https://github.com/abirkel/vespera/actions/workflows/build.yml/badge.svg)](https://github.com/abirkel/vespera/actions/workflows/build.yml)

## Why this base

| Candidate | Verdict |
| --- | --- |
| `ublue-os/kinoite-nvidia` | **Chosen.** Kinoite + `nvidia-open` + a Secure-Boot-signed matching kernel + the full 32-bit driver stack + negativo17 codecs. |
| `bazzite` / `bazzite-nvidia-open` | Replaces Discover with Bazaar, masks the appstream cache refresh, overrides branding, defaults and the update stack. Undoing all that is more work than adding to Kinoite. |
| `aurora-dx` | GNOME-adjacent developer focus; the DX layer is mostly unwanted here. |
| `fedora/fedora-kinoite` | Means owning the NVIDIA kmod signing chain. |

The base ships Fedora's kernel rebuilt and signed with ublue's MOK, which is what
lets prebuilt out-of-tree modules load under Secure Boot. **Do not swap the
kernel** — that breaks the signing chain and every kmod with it.

## Repository layout

```
Containerfile                  base ARGs, akmods mount, one RUN, then bootc lint
Justfile                       just check, build, rechunk, disk, gen-keys
cosign.pub                     public signing key, baked into the image
build_files/
  build.sh                     runs [0-9][0-9]-*.sh in glob order
  lib/common.sh                log/warn/die, retry, fetch, copr_install, repo_install
  00-dnf-policy.sh             install_weak_deps=False  (must be first)
  10-packages-fedora.sh        Fedora packages, one transaction
  20-packages-thirdparty.sh    negativo17, Terra, COPRs, ScopeBuddy, cicpoffs
  30-kmods.sh                  v4l2loopback (akmods), yeetmouse
  40-fonts.sh                  Nerd Fonts, core fonts
  50-flatpaks.sh               validates the preinstall.d declarations
  60-system-config.sh          system_files/, groups, samba, /etc hygiene
  70-services.sh               systemd unit state
  80-image-info.sh             image-info.json; asserts branding is stock
  85-signing.sh                cosign key + registries.d + policy.json
  99-cleanup.sh                repo state, sanity checks, /var and /boot cleanup
system_files/                  copied to / verbatim (rsync -aK)
disk_config/{disk,iso-kde}.toml  bootc-image-builder configs
.github/workflows/build.yml      build, rechunk, sign, push, attest
.github/workflows/build-disk.yml ISO / qcow2 / raw
.github/renovate.json5           digest pinning
```

## Getting started

### 1. Signing keys (required)

```bash
just gen-keys
gh secret set SIGNING_SECRET < cosign.key
git add cosign.pub
shred -u cosign.key
```

### 2. Check, then build

```bash
just check          # syntax, shellcheck, yaml, toml, layout — what CI runs first
just build          # full local build (~40 GB free)
just build-fast     # skips MS fonts and the yeetmouse kmod
just rechunk        # split into per-package layers (see Update download size)
just diff-base      # package diff against kinoite-nvidia
```

### 3. Install

```bash
sudo bootc switch --enforce-container-sigpolicy ghcr.io/abirkel/vespera:latest
# or build media:
just disk iso
```

## Disk and ISO artifacts

```bash
just disk iso        # anaconda-iso, disk_config/iso-kde.toml
just disk qcow2      # disk_config/disk.toml
just run-vm          # boot the qcow2 to smoke-test
```

or run the **Build disk images** workflow manually.

## 4. First boot

1. **Log out and back in once.** `ublue-system-setup.service` adds the account to
   `libvirt`, `plugdev` and `gamemode`; group membership only applies to new
   sessions.
2. **Flatpaks install in the background** via `vespera-flatpak-setup.service` —
   `journalctl -u vespera-flatpak-setup`.
3. **`ujust image-status`** — image ref, NVIDIA driver and kmod state, virt sockets,
   podman, whether each out-of-tree kmod matches the booted kernel, all four Discover
   backends.
4. **`ujust check-overlays`** confirms Flatpak games get GPU acceleration and that
   the layer branch still matches their runtime. **`ujust check-ntsync`** confirms the
   ntsync device is present and 0666.
5. **`ujust setup-lact`** for GPU fan curves.
6. Shell is unchanged (bash). `zsh` is installed with fish-like plugins wired up in
   `/etc/skel/.zshrc`; `chsh -s /usr/bin/zsh` to switch. Existing accounts do not get
   `/etc/skel` — copy the file across by hand.

Help recipes: `ujust help-smb`, `help-iphone`, `help-audio`, `help-gamescope`.
