#!/usr/bin/env bash
# Fetch the prebuilt Android libmpv (mpv 0.41 + FFmpeg, AudioTrack/AAudio outputs) that the Android
# build links against and ships, and unpack it into the app's jniLibs.
#
# Source: dev.jdtech.mpv:libmpv on Maven Central (github.com/jarnedemeulemeester/libmpv-android,
# built from mpv-android's buildscripts). Pinned by version AND sha256: the libraries are linked
# into the APK, so a different archive must be a deliberate change here, never a silent one.
#
# The .so files land in src-tauri/gen/android/app/src/main/jniLibs/<abi>/, which is gitignored
# (`/src/main/jniLibs/**/*.so`). src-tauri/build.rs points the Rust linker at the same directory
# when building for Android, so libapp_lib.so resolves libmpv.so/libavcodec.so at link time and
# Gradle packages the very same files.
#
# Usage: scripts/android/fetch-libmpv.sh [abi ...]   (default: arm64-v8a x86_64)
set -euo pipefail

VERSION=1.0.0
SHA256=df146592480fc8418415a06b1f1a1d6318b0088e21f52254b0e9a82b61ca8fa2
URL="https://repo1.maven.org/maven2/dev/jdtech/mpv/libmpv/${VERSION}/libmpv-${VERSION}.aar"

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
jni="$root/src-tauri/gen/android/app/src/main/jniLibs"
cache="${LIMUSIC_ANDROID_CACHE:-$root/target/android-deps}"
abis=("$@")
[ ${#abis[@]} -eq 0 ] && abis=(arm64-v8a x86_64)

mkdir -p "$cache"
aar="$cache/libmpv-${VERSION}.aar"
if [ ! -f "$aar" ] || ! echo "$SHA256  $aar" | sha256sum -c --status; then
  echo "Downloading libmpv-android ${VERSION}..."
  curl -fsSL "$URL" -o "$aar.tmp"
  mv "$aar.tmp" "$aar"
fi
echo "$SHA256  $aar" | sha256sum -c --quiet

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
unzip -q "$aar" 'jni/*' -d "$tmp"
for abi in "${abis[@]}"; do
  if [ ! -d "$tmp/jni/$abi" ]; then
    echo "libmpv-android ${VERSION} has no $abi build" >&2
    exit 1
  fi
  mkdir -p "$jni/$abi"
  # libplayer.so is the AAR's own Java binding (dev.jdtech.mpv.MPVLib); Limusic drives libmpv from
  # Rust, so it is not shipped.
  for so in "$tmp/jni/$abi"/*.so; do
    [ "$(basename "$so")" = libplayer.so ] && continue
    install -m 0644 "$so" "$jni/$abi/"
  done
  echo "libmpv -> $jni/$abi"
done
