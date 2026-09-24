#!/usr/bin/env bash
# Installs NetWho for the current user (no root needed): copies the app to
# ~/.local/share/netwho and adds it to the application menu. Run it from the
# folder you extracted. Re-run it to update; run uninstall.sh to remove.
set -euo pipefail

app="io.github.biptybop.netwho"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
share="${XDG_DATA_HOME:-$HOME/.local/share}"
dest="$share/netwho"

if [[ ! -x "$here/app/netwho" ]]; then
  echo "Run this from the extracted NetWho folder (app/netwho not found)." >&2
  exit 1
fi

rm -rf "$dest"
mkdir -p "$dest"
cp -r "$here/app/." "$dest/"
cp "$here/uninstall.sh" "$dest/uninstall.sh"

for size in 16 22 24 32 48 64 96 128 256 512; do
  dir="$share/icons/hicolor/${size}x${size}/apps"
  mkdir -p "$dir"
  cp "$here/icons/${size}.png" "$dir/$app.png"
done
mkdir -p "$share/icons/hicolor/scalable/apps"
cp "$here/icons/icon.svg" "$share/icons/hicolor/scalable/apps/$app.svg"

mkdir -p "$share/applications"
cat > "$share/applications/$app.desktop" <<DESKTOP
[Desktop Entry]
Type=Application
Name=NetWho
GenericName=Network Scanner
Comment=See every device on your network
Exec=$dest/netwho
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
command -v kbuildsycoca6 >/dev/null && kbuildsycoca6 --noincremental >/dev/null 2>&1 || true

echo "Installed. NetWho is in your application menu (Internet), or run: $dest/netwho"
echo "You can delete the downloaded folder now."
