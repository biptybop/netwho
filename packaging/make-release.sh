#!/usr/bin/env bash
# Builds signed Android APKs and a Linux tarball for the version in
# pubspec.yaml, plus SHA256SUMS, into dist/<version>/.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"
version="$(sed -n 's/^version: \([0-9.]*\).*/\1/p' pubspec.yaml)"
out="dist/$version"

if ! grep -q "applicationVersion: '$version'" lib/ui/app_menu.dart; then
  echo "The About dialog (lib/ui/app_menu.dart) doesn't say $version; update it first." >&2
  exit 1
fi

if [[ -n "$(git status --porcelain)" ]]; then
  echo "Working tree has uncommitted changes; commit first so the release matches the tag." >&2
  exit 1
fi

rm -rf "$out"
mkdir -p "$out"

flutter build apk --release --split-per-abi
for abi in arm64-v8a armeabi-v7a x86_64; do
  cp "build/app/outputs/flutter-apk/app-$abi-release.apk" "$out/netwho-$version-android-$abi.apk"
done

flutter build linux --release
name="netwho-$version-linux-x64"
stage="$(mktemp -d)/$name"
mkdir -p "$stage/icons"
cp -r build/linux/x64/release/bundle "$stage/app"
cp packaging/linux-release/install.sh packaging/linux-release/uninstall.sh "$stage/"
cp assets/icon/icon.svg "$stage/icons/icon.svg"
for size in 16 22 24 32 48 64 96 128 256 512; do
  magick assets/icon/icon.png -resize "${size}x${size}" "$stage/icons/$size.png" 2>/dev/null \
    || convert assets/icon/icon.png -resize "${size}x${size}" "$stage/icons/$size.png"
done
cp LICENSE "$stage/" 2>/dev/null || true
tar -C "$(dirname "$stage")" -czf "$out/$name.tar.gz" "$name"
rm -rf "$(dirname "$stage")"

(cd "$out" && sha256sum -- * > SHA256SUMS)
echo
echo "Release files in $out:"
cat "$out/SHA256SUMS"
