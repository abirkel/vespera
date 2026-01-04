# Vespera Flatpak Management

## How It Works

Vespera uses a **two-stage flatpak installation** approach:

1. **Bazzite Base** (`bazzite-flatpak-manager.service`) runs first:
   - Sets up Flathub remote
   - Disables Fedora flatpak repos
   - Installs Protontricks
   - Applies flatpak overrides (Firefox, LibreOffice, etc.)

2. **Vespera Layer** (`vespera-flatpak-manager.service`) runs after:
   - Installs flatpaks from `vespera-flatpaks.list`
   - Updates all system flatpaks
   - Runs automatically on first boot

## Files

- **`vespera-flatpaks.list`** - List of flatpaks to install
- **`/usr/libexec/vespera-flatpak-manager`** - Installation script
- **`/usr/lib/systemd/system/vespera-flatpak-manager.service`** - Systemd service
- **`/usr/share/flatpak/preinstall.d/firefox.preinstall`** - Ensures Firefox stays installed

## Adding Flatpaks

Edit `vespera-flatpaks.list` and add the flatpak ID:

```
# Comment lines start with #
org.mozilla.firefox
org.kde.krita
io.podman_desktop.PodmanDesktop
```

## Manual Installation

Users can manually trigger installation:

```bash
ujust install-vespera-flatpaks
```

Or list what will be installed:

```bash
ujust list-vespera-flatpaks
```

## Preinstall Files

Preinstall files in `/usr/share/flatpak/preinstall.d/` tell flatpak to keep certain apps installed even during system updates. Format:

```ini
[Flatpak Preinstall org.mozilla.firefox]
Branch=stable
IsRuntime=false
```

See: https://docs.flatpak.org/en/latest/flatpak-command-reference.html#flatpak-preinstall
