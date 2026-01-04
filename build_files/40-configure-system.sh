#!/usr/bin/bash
set -xeuo pipefail

echo "Configuring system for development..."

# Restore Konsole as default terminal (undo Bazzite's Ptyxis changes)
echo "Restoring Konsole as default terminal..."

# Remove Ptyxis Ctrl+Alt+T shortcut
if [[ -f /usr/share/applications/org.gnome.Ptyxis.desktop ]]; then
    sed -i '/X-KDE-Shortcuts=Ctrl+Alt+T/d' /usr/share/applications/org.gnome.Ptyxis.desktop
fi

# Remove Ptyxis from KDE global shortcuts
rm -f /usr/share/kglobalaccel/org.gnome.Ptyxis.desktop

# Restore Konsole Ctrl+Alt+T shortcut
if [[ -f /usr/share/applications/org.kde.konsole.desktop ]]; then
    # Add shortcut if not present
    if ! grep -q "X-KDE-Shortcuts=Ctrl+Alt+T" /usr/share/applications/org.kde.konsole.desktop; then
        sed -i '/^\[Desktop Entry\]/a X-KDE-Shortcuts=Ctrl+Alt+T' /usr/share/applications/org.kde.konsole.desktop
    fi
fi

# Update KDE taskbar to use Konsole instead of Ptyxis
if [[ -f /usr/share/plasma/plasmoids/org.kde.plasma.taskmanager/contents/config/main.xml ]]; then
    sed -i 's|applications:org.gnome.Ptyxis.desktop|applications:org.kde.konsole.desktop|g' \
        /usr/share/plasma/plasmoids/org.kde.plasma.taskmanager/contents/config/main.xml
fi

# Configure Samba for easy file sharing (from Aurora)
echo "Configuring Samba..."
mkdir -p /var/lib/samba/usershares
chown -R root:usershares /var/lib/samba/usershares
firewall-offline-cmd --service=samba --service=samba-client
setsebool -P samba_enable_home_dirs=1
setsebool -P samba_export_all_ro=1
setsebool -P samba_export_all_rw=1
# Remove [homes] section from smb.conf (security)
sed -i '/^\[homes\]/,/^\[/{/^\[homes\]/d;/^\[/!d}' /etc/samba/smb.conf

# Load iptable_nat module for podman-in-podman (from Bazzite-DX)
echo "Configuring kernel modules for containers..."
mkdir -p /etc/modules-load.d
cat >>/etc/modules-load.d/ip_tables.conf <<EOF
iptable_nat
EOF

# Import just commands
echo "import \"/usr/share/ublue-os/just/95-vespera.just\"" >> /usr/share/ublue-os/justfile

echo "System configuration complete"
