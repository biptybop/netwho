#!/usr/bin/env bash
# Removes NetWho installed by install.sh. Pass --purge to also delete your
# remembered devices and settings.
set -euo pipefail

app="io.github.biptybop.netwho"
share="${XDG_DATA_HOME:-$HOME/.local/share}"

rm -rf "$share/netwho"
rm -f "$share/applications/$app.desktop"
rm -f "$share"/icons/hicolor/*/apps/"$app".png "$share/icons/hicolor/scalable/apps/$app.svg"

if [[ "${1:-}" == "--purge" ]]; then
  rm -rf "$share/$app"
  echo "Removed saved devices and settings too."
fi

update-desktop-database "$share/applications" 2>/dev/null || true
gtk-update-icon-cache -f -t "$share/icons/hicolor" 2>/dev/null || true
command -v kbuildsycoca6 >/dev/null && kbuildsycoca6 --noincremental >/dev/null 2>&1 || true
echo "NetWho removed."
