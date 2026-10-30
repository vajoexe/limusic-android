#!/usr/bin/env bash
# Create the release signing key, once, and point the Gradle build at it.
#
# The key is the app's identity on every device that installs it: Android only accepts an update
# signed with the same key, so this runs once and the result is backed up, never regenerated.
# It refuses to touch a keystore that already exists.
#
# keytool asks for the password itself, so it never appears in arguments, the environment or shell
# history. The keystore is PKCS12, where the key and the store share that one password.
#
# Writes src-tauri/gen/android/keystore.properties (gitignored) with the keystore path and alias
# only. The passwords are never stored: scripts/android/build-release.sh asks for them per build.
#
# Usage: scripts/android/make-release-key.sh
#   LIMUSIC_RELEASE_KEYSTORE  keystore path   (default ~/.local/share/limusic/release.jks)
#   LIMUSIC_RELEASE_ALIAS     key alias       (default vajoexe)
#   LIMUSIC_RELEASE_DNAME     certificate DN  (default CN=vajoexe, OU=Limusic for Android, O=vajoexe)
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
store="${LIMUSIC_RELEASE_KEYSTORE:-$HOME/.local/share/limusic/release.jks}"
alias="${LIMUSIC_RELEASE_ALIAS:-vajoexe}"
dname="${LIMUSIC_RELEASE_DNAME:-CN=vajoexe, OU=Limusic for Android, O=vajoexe}"
props="$root/src-tauri/gen/android/keystore.properties"

if [ -e "$store" ]; then
  echo "A keystore already exists at $store; not creating another." >&2
  echo "Replacing the release key would stop installed copies from updating. Use the existing one." >&2
  exit 1
fi
case "$store" in
  "$root"/*) echo "Refusing to create the keystore inside the repository ($store)." >&2; exit 1 ;;
esac

mkdir -p "$(dirname "$store")"
chmod 700 "$(dirname "$store")"
umask 077

# RSA 4096, valid for 50 years (Android needs the certificate to outlive every update you ship).
keytool -genkeypair \
  -keystore "$store" -storetype PKCS12 \
  -alias "$alias" -keyalg RSA -keysize 4096 -sigalg SHA256withRSA \
  -validity 18250 -dname "$dname"
chmod 600 "$store"

if [ -e "$props" ]; then
  echo "$props already exists; left as it is. It should name storeFile=$store and keyAlias=$alias."
else
  printf 'storeFile=%s\nkeyAlias=%s\n' "$store" "$alias" > "$props"
  chmod 600 "$props"
  echo "Wrote $props (path and alias only, no passwords)."
fi

echo
echo "Created $store. Back it up now, together with its password, somewhere other than this disk."
