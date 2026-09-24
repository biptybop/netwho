#!/usr/bin/env bash
# Creates NetWho's Android release signing key, once, outside the project so
# it can never be committed. Run it in a terminal: it asks for a password.
#
#   ~/.android-keys/netwho-release.jks          the key (back this up)
#   ~/.android-keys/netwho-key.properties       its password, for Gradle
#
# Back up BOTH offline. Lose them and you can never ship an update that
# installs over the existing app; leak them and someone else can.
set -euo pipefail

dir="$HOME/.android-keys"
jks="$dir/netwho-release.jks"
props="$dir/netwho-key.properties"
alias="netwho"

if [[ -e "$jks" ]]; then
  echo "A key already exists at $jks. Not overwriting it." >&2
  exit 1
fi

mkdir -p "$dir"
chmod 700 "$dir"

echo "Choose a strong password (12+ characters) and save it in your password manager."
while true; do
  read -rsp "Key password: " pass; echo
  read -rsp "Again: " again; echo
  if [[ "$pass" != "$again" ]]; then
    echo "They don't match, try again."
  elif (( ${#pass} < 12 )); then
    echo "Use at least 12 characters."
  else
    break
  fi
done

# PKCS12 keystores use one password for the store and the key. The password
# is passed via the environment so it never appears in the process list.
export NETWHO_KEY_PASS="$pass"
keytool -genkeypair \
  -keystore "$jks" -storetype PKCS12 \
  -storepass:env NETWHO_KEY_PASS -keypass:env NETWHO_KEY_PASS \
  -alias "$alias" -keyalg RSA -keysize 4096 -validity 10000 \
  -dname "CN=biptybop, O=NetWho" >/dev/null
chmod 600 "$jks"

umask 077
printf 'storeFile=%s\nkeyAlias=%s\nstorePassword=%s\nkeyPassword=%s\n' \
  "$jks" "$alias" "$pass" "$pass" > "$props"

echo
echo "Created $jks"
echo "Signing certificate fingerprint (safe to publish):"
keytool -list -v -keystore "$jks" -storepass:env NETWHO_KEY_PASS -alias "$alias" \
  | grep -E 'SHA256:' | sed 's/^\s*/  /'
unset pass again NETWHO_KEY_PASS
echo
echo "Now back up $dir somewhere offline (USB stick, password manager attachment)."
