#!/usr/bin/env bash
# Build Limusic: the signed Android release APK (the default), an Android debug APK, or the Linux
# desktop binary. One script for the whole job:
#
#   1. checks every tool the chosen target needs against the versions in REQUIREMENTS below and
#      lists each mismatch (required vs found), then offers to install the missing pieces (y/N);
#   2. finds the release signing key (never creates or replaces one without asking, see SIGNING);
#   3. asks for the key's password, after all of the above, so nothing long runs before it;
#   4. prepares the build once (env.sh, UI dependencies, libmpv), skipping what is already in place;
#   5. builds, then checks the result: signature, certificate, architectures, size and SHA-256;
#   6. cleans up regenerable leftovers only and prints a summary.
#
# Usage: scripts/build.sh [--android | --linux] [options]     (--help for the options)
# With no target flag on a terminal it shows a menu that picks Android after a timeout. Without a
# terminal (CI, a pipe) it never waits: it builds Android, and never installs anything.
#
# Local settings (optional, untracked): ${XDG_CONFIG_HOME:-~/.config}/limusic/build.conf, plain
# KEY=value lines. Read, never sourced. Keys: ANDROID_HOME, MENU_TIMEOUT, APK_BUDGET_MB.
# The environment wins over the file: ANDROID_HOME, LIMUSIC_BUILD_MENU_TIMEOUT, LIMUSIC_APK_BUDGET_MB.
#
# SIGNING. The release key is the app's identity: Android installs an update only over an app
# signed with the same key. So this script never regenerates, moves or overwrites a keystore. If
# none exists it explains that and offers scripts/android/make-release-key.sh, which only ever
# creates a new one. The password is read from the terminal with echo off, handed to keytool and
# Gradle through the environment for this one build (never as an argument, never written to a
# file or the log), and unset when the build ends.
set -euo pipefail
# Decimal points in every number this script prints or parses, whatever the user's locale.
export LC_NUMERIC=C

# ---- REQUIREMENTS (keep in step with README.md "Building") -------------------------------------
RUST_MIN=1.80                     # src-tauri/Cargo.toml rust-version
TAURI_CLI_MAJOR=2
NODE_RANGE="^20.19.0 || >=22.12.0" # vite 8 (ui/package.json)
PNPM_MAJOR=10
JDK_MAJORS="17 21"                # Gradle 9 + AGP 9 (README: JDK 17)
SDK_PLATFORM="platforms;android-37.0"
SDK_BUILD_TOOLS="build-tools;37.0.0"
SDK_NDK="ndk;28.2.13676358"
SDK_PLATFORM_TOOLS="platform-tools"
ANDROID_RUST_TARGETS="aarch64-linux-android x86_64-linux-android"
LINUX_PKGCONFIG="mpv webkit2gtk-4.1 gtk+-3.0 openssl librsvg-2.0"
# -------------------------------------------------------------------------------------------------

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
android_dir="$root/src-tauri/gen/android"
props="$android_dir/keystore.properties"
logs="$root/target/build-logs"
conf="${XDG_CONFIG_HOME:-$HOME/.config}/limusic/build.conf"
started=$(date +%s)

# ---- output ---------------------------------------------------------------------------------------
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  B=$'\e[1m' D=$'\e[2m' R=$'\e[31m' G=$'\e[32m' Y=$'\e[33m' C=$'\e[36m' N=$'\e[0m'
else
  B='' D='' R='' G='' Y='' C='' N=''
fi
step() { printf '\n%s==> %s%s\n' "$B$C" "$*" "$N"; }
ok()   { printf '  %s✓%s %s\n' "$G" "$N" "$*"; }
warn() { printf '  %s!%s %s\n' "$Y" "$N" "$*"; }
die()  { printf '\n%sError:%s %s\n' "$B$R" "$N" "$*" >&2; exit 1; }

interactive() { [ -t 0 ] && [ -r /dev/tty ]; }
# y/N on the terminal. Anything but y/yes is no, and so is having no terminal.
confirm() {
  interactive || return 1
  local a
  read -rp "  $1 [y/N] " a </dev/tty || return 1
  case "$a" in y|Y|yes|YES|Yes) return 0 ;; *) return 1 ;; esac
}

usage() {
  cat <<EOF
${B}Usage:${N} scripts/build.sh [target] [options]

${B}Targets${N} (pick one; with none, a menu on a terminal, else Android)
  --android        Signed universal release APK, arm64-v8a + x86_64 (default)
  --linux          Linux desktop build (cargo tauri build)

${B}Options${N}
  --debug          Android: unsigned-key debug APK instead of the release (no password needed)
  --abi LIST       Android debug only: x86_64 (default), arm64 or both
  --bundles LIST   Linux: also package these bundles (deb, rpm, appimage). Default: binary only,
                   since a locally built bundle is not portable (docs/BUILD-PLATFORMS.md)
  --timeout SECS   Menu timeout before Android is picked (default 10, 0 = no wait)
  --check          Check the toolchain and the signing key, then stop
  -h, --help       This help

${B}Settings${N}
  $conf
  holds optional KEY=value lines: ANDROID_HOME, MENU_TIMEOUT, APK_BUDGET_MB.
  Environment overrides: ANDROID_HOME, LIMUSIC_BUILD_MENU_TIMEOUT, LIMUSIC_APK_BUDGET_MB,
  and for CI signing LIMUSIC_ANDROID_STORE_FILE / _KEY_ALIAS / _STORE_PASSWORD.

${B}Output${N}
  Release APK  src-tauri/gen/android/app/build/outputs/apk/universal/release/limusic-<version>.apk
  Debug APK    src-tauri/gen/android/app/build/outputs/apk/universal/debug/app-universal-debug.apk
  Linux        target/release/limusic-app
  Logs         target/build-logs/ (kept on failure)
EOF
}

# ---- settings -------------------------------------------------------------------------------------
conf_get() { [ -f "$conf" ] || return 0; sed -n "s/^[[:space:]]*$1[[:space:]]*=[[:space:]]*//p" "$conf" | tail -n1 | sed 's/^"\(.*\)"$/\1/'; }
[ -z "${ANDROID_HOME:-}" ] && [ -n "$(conf_get ANDROID_HOME)" ] && ANDROID_HOME="$(conf_get ANDROID_HOME)"
menu_timeout="${LIMUSIC_BUILD_MENU_TIMEOUT:-$(conf_get MENU_TIMEOUT)}"
menu_timeout="${menu_timeout:-10}"
apk_budget_mb="${LIMUSIC_APK_BUDGET_MB:-$(conf_get APK_BUDGET_MB)}"
apk_budget_mb="${apk_budget_mb:-230}"

target='' debug=0 abi='' bundles='' check_only=0
while [ $# -gt 0 ]; do
  case "$1" in
    --android) target=android ;;
    --linux) target=linux ;;
    --debug) debug=1 ;;
    --abi) abi="${2:-}"; shift ;;
    --bundles) bundles="${2:-}"; shift ;;
    --timeout) menu_timeout="${2:-}"; shift ;;
    --check) check_only=1 ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; echo >&2; die "unknown option: $1" ;;
  esac
  shift
done
case "$menu_timeout" in ''|*[!0-9]*) die "--timeout needs a whole number of seconds, got '$menu_timeout'" ;; esac
case "$abi" in ''|x86_64|arm64|both) ;; *) die "--abi must be x86_64, arm64 or both" ;; esac

# ---- menu -----------------------------------------------------------------------------------------
if [ -z "$target" ]; then
  if interactive && [ "$menu_timeout" -gt 0 ]; then
    printf '\n%sLimusic build%s\n\n' "$B" "$N"
    printf '  %s1%s  Android release APK %s(default)%s\n' "$B$G" "$N" "$D" "$N"
    printf '  %s2%s  Android debug APK (emulator, x86_64)\n' "$B$C" "$N"
    printf '  %s3%s  Linux desktop\n' "$B$C" "$N"
    printf '  %sq%s  Quit\n\n' "$B$Y" "$N"
    choice=''
    for ((left = menu_timeout; left > 0; left--)); do
      printf '\r  Choose [1-3, q], Enter for Android. Android in %s%2ds%s ' "$B" "$left" "$N"
      if read -rsn1 -t 1 choice </dev/tty; then break; fi
      choice=timeout
    done
    echo
    case "$choice" in
      ''|1|timeout) target=android ;;
      2) target=android; debug=1 ;;
      3) target=linux ;;
      q|Q) echo "Nothing built."; exit 0 ;;
      *) die "no such choice: $choice" ;;
    esac
    [ "$choice" = timeout ] && echo "  No choice made, building Android."
  else
    target=android
  fi
fi
[ "$target" = linux ] && [ "$debug" = 1 ] && die "--debug is for --android"
[ "$target" = linux ] && [ -n "$abi" ] && die "--abi is for --android"
[ "$target" = android ] && [ -n "$bundles" ] && die "--bundles is for --linux"
[ "$target" = android ] && [ "$debug" = 0 ] && [ -n "$abi" ] && die "--abi is for --debug: the release always carries both"
[ -z "$abi" ] && abi=x86_64

if [ "$target" = android ]; then
  [ "$debug" = 1 ] && variant="android-debug" || variant="android-release"
else
  variant=linux
fi

mkdir -p "$logs"
log="$logs/$variant-$(date +%Y%m%d-%H%M%S).log"
: >"$log"
current_step=''

# Never leave the password around, whatever ends the script.
cleanup_secrets() { unset LIMUSIC_ANDROID_STORE_PASSWORD LIMUSIC_ANDROID_KEY_PASSWORD 2>/dev/null || true; }
on_exit() {
  local s=$?
  cleanup_secrets
  if [ "$s" -ne 0 ] && [ -n "$current_step" ]; then
    printf '\n%sFailed during: %s%s\n' "$B$R" "$current_step" "$N" >&2
    printf 'Log kept at %s\n' "$log" >&2
  elif [ ! -s "$log" ]; then
    rm -f "$log"
  fi
}
trap on_exit EXIT
trap 'exit 130' INT TERM

# Runs a command with its output on screen and in the log.
logged() { "$@" 2>&1 | tee -a "$log"; return "${PIPESTATUS[0]}"; }

# ---- version helpers ------------------------------------------------------------------------------
ver_ge() { [ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | head -n1)" = "$2" ]; }
first_ver() { grep -oE '[0-9]+(\.[0-9]+)+' | head -n1; }
node_ok() { # NODE_RANGE, spelled out
  local v=$1 major=${1%%.*}
  { [ "$major" -eq 20 ] && ver_ge "$v" 20.19.0; } || ver_ge "$v" 22.12.0
}

# Each mismatch: what, required, found, and how it would be fixed (a fix kind and its argument).
mm_what=() mm_req=() mm_have=() mm_fix=()
mismatch() { mm_what+=("$1"); mm_req+=("$2"); mm_have+=("$3"); mm_fix+=("$4"); }

have_pacman() { command -v pacman >/dev/null 2>&1; }

find_sdk() {
  local d
  for d in "${ANDROID_HOME:-}" "${ANDROID_SDK_ROOT:-}" "$HOME/Android/Sdk"; do
    [ -n "$d" ] && [ -d "$d" ] && { echo "$d"; return; }
  done
}
sdkmanager_bin() {
  local s
  for s in "$sdk/cmdline-tools/latest/bin/sdkmanager" "$(command -v sdkmanager 2>/dev/null || true)"; do
    [ -n "$s" ] && [ -x "$s" ] && { echo "$s"; return; }
  done
}
sdk_has() { # sdkmanager package id -> its directory
  [ -d "$sdk/$(echo "$1" | tr ';' '/')" ]
}

# A JDK the build can use: JAVA_HOME if it is a supported one, else the first supported one found.
jdk_major() { "$1/bin/java" -version 2>&1 | sed -n 's/.*version "\([0-9]*\).*/\1/p' | head -n1; }
find_jdk() {
  local j m
  if [ -n "${JAVA_HOME:-}" ] && [ -x "$JAVA_HOME/bin/java" ]; then
    m="$(jdk_major "$JAVA_HOME")"
    case " $JDK_MAJORS " in *" $m "*) echo "$JAVA_HOME"; return ;; esac
  fi
  for j in $(find /usr/lib/jvm -maxdepth 1 -mindepth 1 2>/dev/null | sort); do
    [ -x "$j/bin/java" ] || continue
    m="$(jdk_major "$j")"
    case " $JDK_MAJORS " in *" $m "*) echo "$j"; return ;; esac
  done
}

check_common() {
  local v
  if command -v rustc >/dev/null && command -v cargo >/dev/null; then
    v="$(rustc --version | first_ver)"
    ver_ge "$v" "$RUST_MIN" && ok "Rust $v" || mismatch "Rust" ">= $RUST_MIN" "$v" "rustup-update:"
  else
    mismatch "Rust (rustc, cargo)" ">= $RUST_MIN" "missing" "manual:install rustup (https://rustup.rs), then: rustup default stable"
  fi
  if command -v cargo >/dev/null && v="$(cargo tauri --version 2>/dev/null | first_ver)" && [ -n "$v" ]; then
    [ "${v%%.*}" = "$TAURI_CLI_MAJOR" ] && ok "Tauri CLI $v" || mismatch "Tauri CLI" "$TAURI_CLI_MAJOR.x" "$v" "cargo-tauri:"
  else
    mismatch "Tauri CLI" "$TAURI_CLI_MAJOR.x" "missing" "cargo-tauri:"
  fi
  if command -v node >/dev/null; then
    v="$(node --version | first_ver)"
    node_ok "$v" && ok "Node.js $v" || mismatch "Node.js" "$NODE_RANGE" "$v" "pacman:nodejs"
  else
    mismatch "Node.js" "$NODE_RANGE" "missing" "pacman:nodejs"
  fi
  if command -v pnpm >/dev/null; then
    v="$(pnpm --version 2>/dev/null | first_ver)"
    [ "${v%%.*}" = "$PNPM_MAJOR" ] && ok "pnpm $v" || mismatch "pnpm" "$PNPM_MAJOR.x" "${v:-unknown}" "manual:install pnpm $PNPM_MAJOR (corepack prepare pnpm@$PNPM_MAJOR --activate, or your package manager)"
  else
    mismatch "pnpm" "$PNPM_MAJOR.x" "missing" "pacman:pnpm"
  fi
  local t
  for t in curl unzip sha256sum; do
    command -v "$t" >/dev/null && ok "$t" || mismatch "$t" "any" "missing" "pacman:$( [ "$t" = sha256sum ] && echo coreutils || echo "$t")"
  done
}

check_android() {
  local v t installed
  if command -v rustup >/dev/null; then
    installed="$(rustup target list --installed 2>/dev/null)"
    for t in $ANDROID_RUST_TARGETS; do
      grep -qx "$t" <<<"$installed" && ok "Rust target $t" || mismatch "Rust target $t" "installed" "missing" "rustup-target:$t"
    done
  else
    mismatch "rustup (for the Android Rust targets)" "installed" "missing" "manual:install rustup (https://rustup.rs)"
  fi
  jdk="$(find_jdk)"
  if [ -n "$jdk" ]; then
    ok "JDK $(jdk_major "$jdk") ($jdk)"
    if [ -n "${JAVA_HOME:-}" ] && [ "$JAVA_HOME" != "$jdk" ]; then
      warn "JAVA_HOME is JDK $(jdk_major "$JAVA_HOME" 2>/dev/null || echo '?'); this build uses $jdk instead"
    fi
  else
    v="$( [ -n "${JAVA_HOME:-}" ] && jdk_major "$JAVA_HOME" || (command -v java >/dev/null && java -version 2>&1 | first_ver) || echo missing)"
    mismatch "JDK" "$(echo "$JDK_MAJORS" | sed 's/ / or /')" "${v:-missing}" "pacman:jdk17-openjdk"
  fi
  # Not `ldconfig | grep -q`: with pipefail, grep quitting early fails the pipe.
  if grep -q 'libclang\.so' <<<"$(ldconfig -p 2>/dev/null)" || [ -n "${LIBCLANG_PATH:-}" ]; then
    ok "libclang (bindgen)"
  else
    mismatch "libclang (bindgen)" "any" "missing" "pacman:clang"
  fi
  sdk="$(find_sdk)"
  if [ -z "$sdk" ]; then
    mismatch "Android SDK" "a directory in ANDROID_HOME" "not found" \
      "manual:install the Android command-line tools into an SDK directory and set ANDROID_HOME (or ANDROID_HOME= in $conf)"
    return
  fi
  ok "Android SDK $sdk"
  for t in "$SDK_PLATFORM" "$SDK_BUILD_TOOLS" "$SDK_NDK" "$SDK_PLATFORM_TOOLS"; do
    sdk_has "$t" && ok "SDK $t" || mismatch "SDK package $t" "installed" "missing" "sdk:$t"
  done
  if [ -z "$(sdkmanager_bin)" ] && grep -q '^sdk:' <<<"$(printf '%s\n' "${mm_fix[@]:-}")"; then
    mismatch "SDK command-line tools (sdkmanager)" "installed" "missing" \
      "manual:install 'Command-line Tools' into $sdk/cmdline-tools/latest (developer.android.com/studio#command-line-tools-only)"
  fi
}

check_linux() {
  local p v pkg
  if ! command -v pkg-config >/dev/null; then
    mismatch "pkg-config" "any" "missing" "pacman:pkgconf"
    return
  fi
  ok "pkg-config"
  for p in $LINUX_PKGCONFIG; do
    if v="$(pkg-config --modversion "$p" 2>/dev/null)"; then
      ok "$p $v"
    else
      case "$p" in
        mpv) pkg=mpv ;; webkit2gtk-4.1) pkg=webkit2gtk-4.1 ;; gtk+-3.0) pkg=gtk3 ;;
        openssl) pkg=openssl ;; librsvg-2.0) pkg=librsvg ;; *) pkg='' ;;
      esac
      mismatch "$p (development files)" "installed" "missing" "pacman:$pkg"
    fi
  done
}

report_mismatches() {
  local i
  printf '\n  %sThese do not match what the %s build needs:%s\n\n' "$B$Y" "$variant" "$N"
  printf '  %-40s %-24s %s\n' "What" "Required" "Found"
  for i in "${!mm_what[@]}"; do
    printf '  %-40s %-24s %s%s%s\n' "${mm_what[$i]}" "${mm_req[$i]}" "$R" "${mm_have[$i]}" "$N"
  done
}

# Installs only what the mismatches name, after one y/N. Nothing system-wide but `pacman -S --needed`
# for the listed packages, and only on Arch-based systems.
install_mismatches() {
  local i kind arg pkgs=() sdkpkgs=() targets=() manual=() tauri=0 rustup_update=0
  for i in "${!mm_fix[@]}"; do
    kind="${mm_fix[$i]%%:*}" arg="${mm_fix[$i]#*:}"
    case "$kind" in
      pacman) if have_pacman && [ -n "$arg" ]; then pkgs+=("$arg"); else manual+=("${mm_what[$i]}: install it with your package manager"); fi ;;
      sdk) sdkpkgs+=("$arg") ;;
      rustup-target) targets+=("$arg") ;;
      cargo-tauri) tauri=1 ;;
      rustup-update) rustup_update=1 ;;
      manual) manual+=("${mm_what[$i]}: $arg") ;;
    esac
  done
  if [ ${#manual[@]} -gt 0 ]; then
    printf '\n  %sThis script cannot install these for you:%s\n' "$B" "$N"
    printf '    - %s\n' "${manual[@]}"
    die "install them and run the script again"
  fi
  printf '\n  %sTo fix them it would run:%s\n' "$B" "$N"
  [ ${#pkgs[@]} -gt 0 ] && printf '    sudo pacman -S --needed %s\n' "${pkgs[*]}"
  [ $rustup_update = 1 ] && printf '    rustup update stable\n'
  [ ${#targets[@]} -gt 0 ] && printf '    rustup target add %s\n' "${targets[*]}"
  [ $tauri = 1 ] && printf "    cargo install tauri-cli --version '^%s' --locked\n" "$TAURI_CLI_MAJOR"
  [ ${#sdkpkgs[@]} -gt 0 ] && printf '    sdkmanager %s   (in %s; may ask you to accept licenses)\n' "$(printf "'%s' " "${sdkpkgs[@]}")" "$sdk"
  echo
  if ! interactive; then
    die "not on a terminal, so nothing was installed. Run the commands above, or run this script in a terminal."
  fi
  confirm "Install these now?" || { echo; echo "Nothing installed. Run the commands above yourself, then try again."; exit 1; }
  current_step="installing dependencies"
  [ ${#pkgs[@]} -gt 0 ] && logged sudo pacman -S --needed "${pkgs[@]}"
  [ $rustup_update = 1 ] && logged rustup update stable
  [ ${#targets[@]} -gt 0 ] && logged rustup target add "${targets[@]}"
  [ $tauri = 1 ] && logged cargo install tauri-cli --version "^$TAURI_CLI_MAJOR" --locked
  [ ${#sdkpkgs[@]} -gt 0 ] && "$(sdkmanager_bin)" --sdk_root="$sdk" "${sdkpkgs[@]}" </dev/tty
  current_step=''
}

run_checks() {
  step "Checking the toolchain for $variant"
  mm_what=() mm_req=() mm_have=() mm_fix=()
  check_common
  if [ "$target" = android ]; then check_android; else check_linux; fi
}

run_checks
if [ ${#mm_what[@]} -gt 0 ]; then
  report_mismatches
  install_mismatches
  step "Checking again after the install"
  hash -r
  run_checks
  if [ ${#mm_what[@]} -gt 0 ]; then
    report_mismatches
    die "still not right after installing; nothing was built"
  fi
fi
ok "Everything the $variant build needs is in place"

# ---- signing key ----------------------------------------------------------------------------------
store='' alias='' key_sha=''
prop() { [ -f "$props" ] || return 0; sed -n "s/^$1=//p" "$props" | tail -n1; }
default_store="${LIMUSIC_RELEASE_KEYSTORE:-$HOME/.local/share/limusic/release.jks}"
default_alias="${LIMUSIC_RELEASE_ALIAS:-vajoexe}"

find_key() {
  step "Looking for the release signing key"
  store="${LIMUSIC_ANDROID_STORE_FILE:-$(prop storeFile)}"
  alias="${LIMUSIC_ANDROID_KEY_ALIAS:-$(prop keyAlias)}"
  if [ -n "$store" ]; then
    [ -n "$alias" ] || die "keystore.properties names a keystore but no keyAlias. Add keyAlias=<alias> to $props"
    # Named but not there: maybe an unmounted disk, maybe a typo. Never "fix" this with a new key.
    [ -f "$store" ] || die "the configured keystore is not there: $store
  Check that the disk holding it is mounted and that $props points at it.
  A new key would not replace it: apps signed with the old one could no longer be updated."
    ok "Keystore $store (alias $alias)"
    return
  fi
  if [ -f "$default_store" ]; then
    warn "Found a keystore at $default_store, but nothing points the build at it."
    echo "  The build reads the keystore path and key alias from $props"
    echo "  (path and alias only, no password)."
    if confirm "Write that file for $default_store with alias '$default_alias'?"; then
      umask 077
      printf 'storeFile=%s\nkeyAlias=%s\n' "$default_store" "$default_alias" >"$props"
      ok "Wrote $props"
      store="$default_store" alias="$default_alias"
      return
    fi
    die "no signing key configured. Set LIMUSIC_ANDROID_STORE_FILE and LIMUSIC_ANDROID_KEY_ALIAS, or write $props"
  fi
  cat <<EOF

  ${B}No release signing key was found.${N}

  Android only installs an update over an existing app when both were signed with the same key,
  so a release needs a key that you keep for as long as the app exists. Lose it and everyone has
  to uninstall (and lose the app's data) to install a build signed with a new one.

  This can create one now with scripts/android/make-release-key.sh:
    - the key is stored at $default_store, outside the repository;
    - keytool will ask you to choose its password. Pick one you will remember, and keep it with a
      backup of the .jks file somewhere other than this disk (a password manager, say);
    - nothing about the password is written anywhere by this script.

  If you already have a key elsewhere, answer no and point LIMUSIC_ANDROID_STORE_FILE and
  LIMUSIC_ANDROID_KEY_ALIAS (or $props) at it. For a test build without a key use --debug.

EOF
  confirm "Create a new release key now?" || { echo "No key created. Nothing was built."; exit 1; }
  confirm "This creates a new signing identity for your builds. Continue?" || { echo "No key created. Nothing was built."; exit 1; }
  current_step="creating the signing key"
  "$root/scripts/android/make-release-key.sh" </dev/tty
  current_step=''
  store="$(prop storeFile)" alias="$(prop keyAlias)"
  [ -n "$store" ] && [ -f "$store" ] || die "the key was not created"
}

# The SHA-256 of the key's certificate, as apksigner prints it (lowercase hex, no colons).
key_cert_sha() {
  keytool -list -v -keystore "$store" -alias "$alias" -storepass:env LIMUSIC_ANDROID_STORE_PASSWORD 2>/dev/null |
    sed -n 's/^[[:space:]]*SHA256:[[:space:]]*//p' | head -n1 | tr -d ':' | tr 'A-F' 'a-f' || true
}

ask_password() {
  # keytool comes with the JDK the checks picked.
  export PATH="$jdk/bin:$PATH"
  if [ -n "${LIMUSIC_ANDROID_STORE_PASSWORD:-}" ]; then
    # CI: the password came from the environment. One try, no prompt.
    key_sha="$(key_cert_sha)"
    [ -n "$key_sha" ] || die "the password in LIMUSIC_ANDROID_STORE_PASSWORD did not open the key"
  else
    interactive || die "no terminal to ask for the keystore password (set LIMUSIC_ANDROID_STORE_PASSWORD in CI)"
    step "Unlocking the signing key"
    while :; do
      IFS= read -rsp "  Password for $(basename "$store"): " LIMUSIC_ANDROID_STORE_PASSWORD </dev/tty || die "no password entered"
      echo
      export LIMUSIC_ANDROID_STORE_PASSWORD
      if [ -n "$LIMUSIC_ANDROID_STORE_PASSWORD" ]; then
        key_sha="$(key_cert_sha)"
        [ -n "$key_sha" ] && break
      fi
      # Deliberately the same message for a wrong password and a missing alias.
      printf '  %sWrong password, or the key lookup failed.%s\n' "$R" "$N"
      if ! confirm "Try again?"; then
        cleanup_secrets
        echo "Nothing was built."
        exit 1
      fi
    done
  fi
  export LIMUSIC_ANDROID_STORE_PASSWORD
  # PKCS12 keeps one password for the store and the key.
  export LIMUSIC_ANDROID_KEY_PASSWORD="${LIMUSIC_ANDROID_KEY_PASSWORD:-$LIMUSIC_ANDROID_STORE_PASSWORD}"
  ok "Key unlocked (certificate SHA-256 ${key_sha:0:16}...)"
}

if [ "$variant" = android-release ]; then
  find_key
fi
if [ "$check_only" = 1 ]; then
  echo
  echo "Checks done, nothing built (--check)."
  exit 0
fi
[ "$variant" = android-release ] && ask_password

# ---- preparation ----------------------------------------------------------------------------------
human() { awk -v b="$1" 'BEGIN { if (b >= 1048576) printf "%.1f MB", b/1048576; else printf "%.0f KB", b/1024 }'; }

prepare_ui() {
  step "UI dependencies"
  local stamp="$root/ui/node_modules/.modules.yaml"
  if [ -f "$stamp" ] && [ ! "$root/ui/pnpm-lock.yaml" -nt "$stamp" ] && [ ! "$root/ui/package.json" -nt "$stamp" ]; then
    ok "Up to date with pnpm-lock.yaml, not reinstalled"
  else
    current_step="installing the UI dependencies (pnpm install)"
    (cd "$root/ui" && logged pnpm install --frozen-lockfile)
    ok "Installed"
  fi
}

prepare_android_env() {
  step "Android build environment"
  export ANDROID_HOME="$sdk" JAVA_HOME="$jdk"
  # The documented NDK, not just the newest one env.sh would pick.
  export NDK_HOME="$sdk/ndk/${SDK_NDK#ndk;}"
  current_step="setting up the Android environment (scripts/android/env.sh)"
  # shellcheck source=android/env.sh
  source "$root/scripts/android/env.sh" >>"$log" 2>&1
  ok "SDK $ANDROID_HOME"
  ok "NDK $NDK_HOME"
  ok "JDK $JAVA_HOME"
}

prepare_libmpv() {
  step "libmpv for Android"
  local fetch="$root/scripts/android/fetch-libmpv.sh" ver sha stamp jni="$android_dir/app/src/main/jniLibs" a ok_all=1
  ver="$(sed -n 's/^VERSION=//p' "$fetch")" sha="$(sed -n 's/^SHA256=//p' "$fetch")"
  stamp="$root/target/android-deps/libmpv.stamp"
  for a in arm64-v8a x86_64; do
    [ -f "$jni/$a/libmpv.so" ] || ok_all=0
  done
  if [ $ok_all = 1 ] && [ -f "$stamp" ] && [ "$(cat "$stamp")" = "$ver $sha" ]; then
    ok "libmpv-android $ver already unpacked, checksum matched when it was"
  else
    current_step="fetching libmpv (scripts/android/fetch-libmpv.sh)"
    logged "$fetch"
    mkdir -p "$(dirname "$stamp")"
    echo "$ver $sha" >"$stamp"
    ok "libmpv-android $ver unpacked"
  fi
}

# ---- Android build and checks ---------------------------------------------------------------------
build_tools_dir() { echo "$sdk/build-tools/${SDK_BUILD_TOOLS#build-tools;}"; }

# ELF e_machine of a library inside the APK: 183 = AArch64, 62 = x86-64.
# `|| true`: unzip dies of SIGPIPE once head has its 20 bytes, which pipefail would count as failure.
elf_machine() { { unzip -p "$1" "$2" 2>/dev/null || true; } | head -c 20 | od -An -tu2 -j18 -N2 2>/dev/null | tr -d ' ' || true; }

verify_apk() { # apk, expected abis...
  local apk=$1; shift
  local bt; bt="$(build_tools_dir)"
  step "Checking the APK"
  current_step="checking the APK"
  local certs
  certs="$("$bt/apksigner" verify --verbose --print-certs "$apk" 2>&1)" || { echo "$certs" | tee -a "$log"; die "apksigner rejected $apk"; }
  echo "$certs" >>"$log"
  schemes="$(echo "$certs" | sed -n 's/^Verified using \(v[0-9.]*\) scheme.*: true$/\1/p' | paste -sd/ -)"
  ok "Signature valid (${schemes:-scheme unknown})"
  # apksigner names the signer by scheme: "Signer #1 certificate" for v1/v2 only, "V3.0 Signer:
  # certificate" once v3 is on. Every signer it lists has to be the one certificate.
  apk_cert="$(echo "$certs" | sed -nE 's/^(Signer #[0-9]+|V[0-9.]+ Signer):? certificate SHA-256 digest: //p' | sort -u | paste -sd' ' -)"
  if [ -n "$key_sha" ]; then
    [ -n "$apk_cert" ] || die "could not read the APK's certificate out of apksigner's output (it is in the log)"
    [ "$apk_cert" = "$key_sha" ] || die "the APK is signed with certificate $apk_cert, not your key's $key_sha"
    ok "Signed with your key ($alias)"
  fi
  local a m want found=''
  for a in "$@"; do
    case "$a" in arm64-v8a) want=183 ;; x86_64) want=62 ;; esac
    m="$(elf_machine "$apk" "lib/$a/libapp_lib.so")"
    [ "$m" = "$want" ] || die "lib/$a/libapp_lib.so is missing or not built for $a (ELF machine '${m:-none}')"
    [ -n "$(unzip -l "$apk" "lib/$a/libmpv.so" 2>/dev/null | grep libmpv.so)" ] || die "lib/$a/libmpv.so is missing"
    found+="$a "
  done
  local extra; extra="$(unzip -Z1 "$apk" 'lib/*' 2>/dev/null | cut -d/ -f2 | sort -u | grep -vxF -f <(printf '%s\n' "$@") || true)"
  [ -z "$extra" ] || warn "unexpected architectures in the APK: $extra"
  abis="${found% }"
  ok "Architectures: $abis (libapp_lib.so and libmpv.so in each)"
  version="$("$bt/aapt2" dump badging "$apk" 2>/dev/null | sed -n "s/.*versionName='\([^']*\)'.*/\1/p" | head -n1)"
  [ -n "$version" ] || die "could not read the version out of $apk"
  ok "Version $version"
}

size_report() { # apk
  local apk=$1 total last_f="$logs/last-size-$variant.txt" last line
  step "Size"
  total=$(stat -c %s "$apk")
  unzip -lv "$apk" | awk '
    $NF ~ /^lib\// { split($NF, p, "/"); g = "lib/" p[2] }
    $NF ~ /\.dex$/ { g = "dex" }
    $NF ~ /^res\// || $NF == "resources.arsc" { g = "res" }
    $NF ~ /^assets\// { g = "assets" }
    NF >= 8 && $1 ~ /^[0-9]+$/ && g != "" { s[g] += $3; g = "" }
    END { for (k in s) printf "  %-18s %8.2f MB\n", k, s[k] / 1048576 }' | sort | tee -a "$log"
  printf '  %-18s %8.2f MB\n' total "$(awk -v b="$total" 'BEGIN { print b / 1048576 }')"
  if [ -f "$last_f" ]; then
    last=$(cat "$last_f")
    line="$(awk -v a="$total" -v b="$last" 'BEGIN { d = a - b; printf "%+.2f MB (%+.1f%%) since the last %s build", d/1048576, (b ? d*100/b : 0), "'"$variant"'" }')"
    if [ "$total" -gt $((last + last / 20)) ]; then warn "$line, more than 5%"; else ok "$line"; fi
  fi
  echo "$total" >"$last_f"
  if [ "$variant" = android-release ] && [ "$total" -gt $((apk_budget_mb * 1048576)) ]; then
    warn "over the ${apk_budget_mb} MB budget (APK_BUDGET_MB). See README.md \"APK size\" for what takes the space."
  fi
  size="$(human "$total")"
}

build_android() {
  local out="$android_dir/app/build/outputs/apk" apk targets=()
  if [ "$variant" = android-release ]; then
    apk="$out/universal/release/app-universal-release.apk"
    targets=(--target aarch64 --target x86_64)
  else
    # One output file whatever the ABIs: Gradle packs only the ones built.
    apk="$out/universal/debug/app-universal-debug.apk"
    case "$abi" in
      x86_64) targets=(--target x86_64) ;;
      arm64) targets=(--target aarch64) ;;
      both) targets=(--target aarch64 --target x86_64) ;;
    esac
  fi
  # Gradle's incremental packager can leave dead space in a reused APK (and a zip some tools
  # reject). The output is rebuilt from scratch every time anyway, so start without it.
  rm -f "$apk"
  step "Building ($variant)"
  current_step="building the APK (cargo tauri android build)"
  local status=0
  if [ "$variant" = android-release ]; then
    # The configuration cache would store the signing values Gradle reads; it is off for this
    # build, and the daemon that saw the password is stopped right after.
    export GRADLE_OPTS="${GRADLE_OPTS:-} -Dorg.gradle.configuration-cache=false"
    (cd "$root" && logged cargo tauri android build "${targets[@]}" --apk) || status=$?
    cleanup_secrets
    (cd "$android_dir" && ./gradlew --stop >/dev/null 2>&1) || true
  else
    (cd "$root" && logged cargo tauri android build --debug "${targets[@]}" --apk) || status=$?
  fi
  [ "$status" -eq 0 ] || exit "$status"
  [ -f "$apk" ] || die "the build finished but $apk is missing (an unsigned release? check the log)"
  current_step=''

  if [ "$variant" = android-release ]; then
    verify_apk "$apk" arm64-v8a x86_64
    artifact="$(dirname "$apk")/limusic-$version.apk"
    cp "$apk" "$artifact"
  else
    case "$abi" in x86_64) verify_apk "$apk" x86_64 ;; arm64) verify_apk "$apk" arm64-v8a ;; both) verify_apk "$apk" arm64-v8a x86_64 ;; esac
    artifact="$apk"
  fi
  sha="$(sha256sum "$artifact" | cut -d' ' -f1)"
  ok "SHA-256 $sha"
  size_report "$artifact"
  # Gradle's own copy is byte for byte the named one: drop it once the copy is proven identical.
  if [ "$variant" = android-release ] && [ "$(sha256sum "$apk" | cut -d' ' -f1)" = "$sha" ]; then
    cleaned+=("Gradle's duplicate app-universal-release.apk ($(human "$(stat -c %s "$apk")"))")
    rm -f "$apk"
  fi
  if [ "$variant" = android-release ]; then
    signature="${schemes} valid, certificate matches $alias"
  else
    signature="${schemes} valid, debug key (not for release)"
  fi
}

# ---- Linux build ----------------------------------------------------------------------------------
build_linux() {
  step "Building (Linux)"
  current_step="building the Linux app (cargo tauri build)"
  local args=(--no-bundle)
  [ -n "$bundles" ] && args=(--bundles "$bundles")
  (cd "$root" && logged cargo tauri build "${args[@]}")
  current_step="checking the Linux build"
  local bin="$root/target/release/limusic-app"
  [ -x "$bin" ] || bin="$root/target/release/limusic"
  [ -x "$bin" ] || die "the build finished but target/release/limusic-app is missing"
  step "Checking the binary"
  local m; m="$(head -c 20 "$bin" | od -An -tu2 -j18 -N2 | tr -d ' ')"
  [ "$m" = 62 ] || die "$bin is not an x86-64 ELF binary (machine ${m:-none})"
  ok "x86-64 ELF"
  local missing; missing="$(ldd "$bin" 2>/dev/null | grep 'not found' || true)"
  [ -z "$missing" ] || { echo "$missing"; die "$bin needs libraries this system does not have"; }
  ok "Every shared library resolves (ldd)"
  ok "libmpv: $(ldd "$bin" | sed -n 's/^[[:space:]]*\(libmpv[^ ]*\).*/\1/p' | head -n1)"
  artifact="$bin"
  abis="x86_64"
  version="$(sed -n 's/^version = "\(.*\)"/\1/p' "$root/Cargo.toml" | head -n1)"
  sha="$(sha256sum "$bin" | cut -d' ' -f1)"
  ok "SHA-256 $sha"
  size="$(human "$(stat -c %s "$bin")")"
  signature="not signed (Linux binaries are not)"
  if [ -n "$bundles" ]; then
    warn "bundles in target/release/bundle/ are for local testing only: they carry this machine's glibc floor"
  fi
}

# ---- cleanup --------------------------------------------------------------------------------------
cleaned=()
tidy() {
  # Old logs, keeping the newest 10 per variant; a failed run's log is never reached here.
  local old n=0 f
  old="$(ls -1t "$logs"/"$variant"-*.log 2>/dev/null | tail -n +11 || true)"
  for f in $old; do rm -f "$f"; n=$((n + 1)); done
  [ $n -gt 0 ] && cleaned+=("$n old $variant log(s) in target/build-logs")
  # Stale unsigned-release leftovers from a build that had no key (never signed, never shippable).
  f="$android_dir/app/build/outputs/apk/universal/release/app-universal-release-unsigned.apk"
  if [ "$target" = android ] && [ -f "$f" ]; then rm -f "$f"; cleaned+=("an old unsigned release APK"); fi
  return 0
}

# ---- run ------------------------------------------------------------------------------------------
artifact='' version='' sha='' size='' abis='' signature='' schemes=''
prepare_ui
if [ "$target" = android ]; then
  prepare_android_env
  prepare_libmpv
  build_android
else
  build_linux
fi
current_step=''
tidy

elapsed=$(($(date +%s) - started))
duration="$(printf '%dm %02ds' $((elapsed / 60)) $((elapsed % 60)))"
rel="${artifact#"$root"/}"

box() {
  # As wide as the longest line, within the terminal.
  local w=40 line cols
  for line in "$@"; do [ $((${#line} + 2)) -gt $w ] && w=$((${#line} + 2)); done
  cols=$(tput cols 2>/dev/null || echo 80)
  [ $w -gt $((cols - 2)) ] && w=$((cols - 2))
  [ $w -lt 40 ] && w=40
  printf '\n%s┌%s┐%s\n' "$G" "$(printf '─%.0s' $(seq 1 $w))" "$N"
  for line in "$@"; do
    # Long values (the path) wrap inside the box rather than past it.
    while [ ${#line} -gt $((w - 2)) ]; do
      printf '%s│%s %-*s %s│%s\n' "$G" "$N" $((w - 2)) "${line:0:$((w - 2))}" "$G" "$N"
      line="              ${line:$((w - 2))}"
    done
    printf '%s│%s %-*s %s│%s\n' "$G" "$N" $((w - 2)) "$line" "$G" "$N"
  done
  printf '%s└%s┘%s\n' "$G" "$(printf '─%.0s' $(seq 1 $w))" "$N"
}
summary=(
  "BUILD SUCCEEDED"
  ""
  "Target        $variant"
  "Version       $version"
  "Architectures $abis"
  "Signature     $signature"
  "Size          $size"
  "Duration      $duration"
  "Artifact      $rel"
  "SHA-256       $sha"
  "Log           ${log#"$root"/}"
)
if [ ${#cleaned[@]} -gt 0 ]; then
  summary+=("" "Cleaned up")
  for c in "${cleaned[@]}"; do summary+=("  - $c"); done
fi
box "${summary[@]}"
echo "$artifact"
