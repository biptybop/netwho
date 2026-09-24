#!/usr/bin/env bash
# Adds NetWho to the desktop application menu (under Internet) using the
# release bundle in place, so a rebuild is picked up without reinstalling.
# Run `flutter build linux --release` first.
set -euo pipefail

app="io.github.biptybop.netwho"
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
bundle="$root/build/linux/x64/release/bundle"
share="${XDG_DATA_HOME:-$HOME/.local/share}"

if [[ ! -x "$bundle/netwho" ]]; then
  echo "No release bundle found. Run: flutter build linux --release" >&2
  exit 1
fi

resize() {  # resize <size> <destination>
  magick "$root/assets/icon/icon.png" -resize "$1x$1" "$2" 2>/dev/null \
    || convert "$root/assets/icon/icon.png" -resize "$1x$1" "$2"
}

for size in 16 22 24 32 48 64 96 128 256 512; do
  dir="$share/icons/hicolor/${size}x${size}/apps"
  mkdir -p "$dir"
  resize "$size" "$dir/$app.png"
done
mkdir -p "$share/icons/hicolor/scalable/apps"
cp "$root/assets/icon/icon.svg" "$share/icons/hicolor/scalable/apps/$app.svg"

mkdir -p "$share/applications"
cat > "$share/applications/$app.desktop" <<DESKTOP
[Desktop Entry]
Type=Application
Name=NetWho
GenericName=Network Scanner
Comment=See every device on your network — no ads, no accounts
Exec=$bundle/netwho
Icon=$app
Terminal=false
Categories=Network;Utility;
Keywords=network;scanner;lan;wifi;devices;ip;ping;port;
StartupNotify=true
StartupWMClass=$app
DESKTOP
chmod +x "$share/applications/$app.desktop"

update-desktop-database "$share/applications" 2>/dev/null || true
gtk-update-icon-cache -f -t "$share/icons/hicolor" 2>/dev/null || true
# KDE caches its menu separately.
command -v kbuildsycoca6 >/dev/null && kbuildsycoca6 --noincremental >/dev/null 2>&1 || true

echo "Installed. NetWho should now appear under Internet in the app menu."
