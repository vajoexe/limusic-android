#!/usr/bin/env bash
# Build the signed arm64 release APK.
#
# app/build.gradle.kts signs release builds with whatever keystore.properties and the
# LIMUSIC_ANDROID_* variables name. keystore.properties (from make-release-key.sh) holds the path
# and alias; this script asks for the password and hands it to Gradle through
# LIMUSIC_ANDROID_STORE_PASSWORD / LIMUSIC_ANDROID_KEY_PASSWORD for this one build. Nothing is
# written to disk: Gradle's configuration cache (which would store the values it reads) is off for
# this build, and the daemon that saw the variables is stopped afterwards.
#
# Usage: scripts/android/build-release.sh      (ANDROID_HOME must be set, see env.sh)
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
android="$root/src-tauri/gen/android"
props="$android/keystore.properties"

prop() { [ -f "$props" ] && sed -n "s/^$1=//p" "$props" | tail -n1; }
store="${LIMUSIC_ANDROID_STORE_FILE:-$(prop storeFile)}"
alias="${LIMUSIC_ANDROID_KEY_ALIAS:-$(prop keyAlias)}"
if [ -z "$store" ] || [ -z "$alias" ]; then
  echo "No signing key configured. Run scripts/android/make-release-key.sh first," >&2
  echo "or set LIMUSIC_ANDROID_STORE_FILE and LIMUSIC_ANDROID_KEY_ALIAS." >&2
  exit 1
fi
[ -f "$store" ] || { echo "Keystore not found: $store" >&2; exit 1; }

if [ -z "${LIMUSIC_ANDROID_STORE_PASSWORD:-}" ]; then
  read -rsp "Password for $store: " LIMUSIC_ANDROID_STORE_PASSWORD </dev/tty
  echo
fi
export LIMUSIC_ANDROID_STORE_PASSWORD
# PKCS12 keeps one password for the store and the key.
export LIMUSIC_ANDROID_KEY_PASSWORD="${LIMUSIC_ANDROID_KEY_PASSWORD:-$LIMUSIC_ANDROID_STORE_PASSWORD}"

# Check the password and alias before a long build. keytool reads it from the environment
# (`:env`), so it never shows up in the process list.
if ! keytool -list -keystore "$store" -alias "$alias" \
    -storepass:env LIMUSIC_ANDROID_STORE_PASSWORD >/dev/null 2>&1; then
  echo "Wrong password, or no key named '$alias' in $store." >&2
  exit 1
fi

source "$root/scripts/android/env.sh" >/dev/null
export GRADLE_OPTS="${GRADLE_OPTS:-} -Dorg.gradle.configuration-cache=false"

status=0
(cd "$root" && cargo tauri android build --target aarch64 --apk) || status=$?
unset LIMUSIC_ANDROID_STORE_PASSWORD LIMUSIC_ANDROID_KEY_PASSWORD
(cd "$android" && ./gradlew --stop >/dev/null 2>&1) || true
[ "$status" -eq 0 ] || exit "$status"

apk="$android/app/build/outputs/apk/universal/release/app-universal-release.apk"
[ -f "$apk" ] || { echo "Build finished but $apk is missing (was it left unsigned?)" >&2; exit 1; }
apksigner="$(ls -d "$ANDROID_HOME"/build-tools/*/ | sort -V | tail -n1)apksigner"
"$apksigner" verify --verbose --print-certs "$apk"
echo
echo "Signed release APK: $apk"
