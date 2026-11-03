#!/usr/bin/env bash
# Build the signed universal release APK and publish it as a GitHub release of the Android port.
#
#   1. preflight: on master, nothing uncommitted, HEAD pushed, gh installed and signed in;
#   2. picks the revision with you (android-port.properties), refuses one Android would see as a
#      downgrade or that is already released, and commits and pushes a changed revision;
#   3. opens the release notes in an editor (a template the first time) and waits for you;
#   4. runs scripts/build.sh --android, which asks for the keystore password itself;
#   5. shows what will be published and asks before anything leaves this machine;
#   6. creates the release as a draft, uploads the APK, downloads it back and compares the
#      SHA-256, and only then publishes it as Latest (the in-app update check reads
#      /releases/latest, so a draft or prerelease would never reach anyone).
#
# Nothing is published without a "y" at step 5. No password or token passes through this script:
# the keystore password goes to build.sh's own prompt, GitHub access is gh's (`gh auth login`).
#
# Usage: scripts/android/publish.sh
# Settings (optional) in ~/.config/limusic/build.conf, the same file build.sh reads:
#   RELEASE_DIR=<dir>   where release notes are kept and the published APK is copied
#                       (default: limusic-apks next to this clone)
#   PUBLISH_REPO=<o/r>  default vajoexe/limusic-android
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$root"
conf="${XDG_CONFIG_HOME:-$HOME/.config}/limusic/build.conf"
conf_get() { [ -f "$conf" ] || return 0; sed -n "s/^[[:space:]]*$1[[:space:]]*=[[:space:]]*//p" "$conf" | tail -n1 | sed 's/^"\(.*\)"$/\1/'; }

repo="${LIMUSIC_PUBLISH_REPO:-$(conf_get PUBLISH_REPO)}"; repo="${repo:-vajoexe/limusic-android}"
release_dir="${LIMUSIC_RELEASE_DIR:-$(conf_get RELEASE_DIR)}"; release_dir="${release_dir:-$(dirname "$root")/limusic-apks}"
props="$root/src-tauri/android-port.properties"

if [ -t 1 ]; then B=$'\e[1m' G=$'\e[32m' Y=$'\e[33m' R=$'\e[31m' N=$'\e[0m'; else B='' G='' Y='' R='' N=''; fi
step() { printf '\n%s==> %s%s\n' "$B" "$*" "$N"; }
ok()   { printf '  %s✓%s %s\n' "$G" "$N" "$*"; }
warn() { printf '  %s!%s %s\n' "$Y" "$N" "$*"; }
die()  { printf '\n%sError:%s %s\n' "$B$R" "$N" "$*" >&2; exit 1; }
[ -t 0 ] && [ -r /dev/tty ] || die "run this from a terminal: it asks questions and build.sh asks for the keystore password"
confirm() { local a; read -rp "  $1 [y/N] " a </dev/tty || return 1; case "$a" in y|Y|yes|YES|Yes) return 0 ;; *) return 1 ;; esac; }

# versionCode as app/build.gradle.kts packs it: two digits each for major, minor, patch, the release
# candidate (99 = final), then the revision. Prints nothing for a version it can't read.
version_code() { # <upstream X.Y.Z[-rc.N]> <revision>
  [[ "$1" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)(-rc\.([0-9]+))?$ ]] || return 0
  local rc="${BASH_REMATCH[5]:-99}"
  echo $(( (((10#${BASH_REMATCH[1]} * 100 + 10#${BASH_REMATCH[2]}) * 100 + 10#${BASH_REMATCH[3]}) * 100 + 10#$rc) * 100 + 10#$2 ))
}

# ---- preflight ------------------------------------------------------------------------------------
step "Preflight"
command -v gh >/dev/null || die "gh (GitHub CLI) is not installed. Install it once with:
    sudo pacman -S github-cli
  then sign in with:  gh auth login"
gh auth status >/dev/null 2>&1 || die "gh is not signed in. Run once:  gh auth login"
ok "gh signed in"
command -v jq >/dev/null || die "jq is not installed (sudo pacman -S jq)"

branch="$(git rev-parse --abbrev-ref HEAD)"
[ "$branch" = master ] || die "on branch $branch; releases are cut from master"
git diff --quiet && git diff --cached --quiet || die "uncommitted changes to tracked files. Commit them first: the APK must match the tagged source"
git fetch -q origin master || die "could not fetch origin"
[ "$(git rev-parse HEAD)" = "$(git rev-parse origin/master)" ] || die "HEAD is not origin/master. Push (or pull) first: the tag is made on GitHub from the pushed commit"
ok "master, clean, pushed ($(git rev-parse --short HEAD))"

upstream="$(jq -r .version src-tauri/tauri.conf.json)"
[ -n "$upstream" ] && [ "$upstream" != null ] || die "no version in src-tauri/tauri.conf.json"
cargo_v="$(sed -n 's/^version *= *"\(.*\)"/\1/p' Cargo.toml | head -1)"
[ "$cargo_v" = "$upstream" ] || die "Cargo.toml says $cargo_v but tauri.conf.json says $upstream"
revision="$(sed -n 's/^revision=//p' "$props" | tr -d '[:space:]')"
[[ "$revision" =~ ^[0-9]+$ ]] || die "no revision=N in $props"

latest_json="$(gh api "repos/$repo/releases/latest" 2>/dev/null || true)"
latest_tag="$(jq -r '.tag_name // empty' <<<"$latest_json" 2>/dev/null || true)"
latest_code=''
if [[ "$latest_tag" =~ ^v?([0-9]+\.[0-9]+\.[0-9]+(-rc\.[0-9]+)?)(-[a-z0-9_]+)?-android\.([0-9]+)$ ]]; then
  latest_up="${BASH_REMATCH[1]}"; latest_rev="${BASH_REMATCH[4]}"
  latest_code="$(version_code "$latest_up" "$latest_rev")"
  ok "latest release: $latest_tag"
else
  warn "no readable latest release on $repo${latest_tag:+ ($latest_tag)}"
fi

# ---- revision -------------------------------------------------------------------------------------
step "Version"
# android-port.properties: 1 for the first release on an upstream version, +1 after that.
suggest="$revision"
if [ -n "$latest_code" ]; then
  if [ "$latest_up" = "$upstream" ]; then
    [ "$revision" -gt "$latest_rev" ] || suggest=$((latest_rev + 1))
  else
    suggest=1
  fi
fi
echo "  Upstream version $upstream, revision in android-port.properties: $revision"
[ "$suggest" = "$revision" ] || echo "  Suggested: $suggest$([ "${latest_up:-}" = "$upstream" ] && echo " (next after $latest_tag)" || echo " (first release on $upstream)")"
read -rp "  Revision to release [$suggest]: " pick </dev/tty || die "no answer"
pick="${pick:-$suggest}"
[[ "$pick" =~ ^[0-9]+$ ]] && [ "$pick" -ge 1 ] && [ "$pick" -le 99 ] || die "revision must be 1-99"
pick=$((10#$pick))
tag="v$upstream-android.$pick"
name="limusic-$upstream-universal-android.$pick.apk"
code="$(version_code "$upstream" "$pick")"
[ -n "$code" ] || die "upstream version $upstream is not X.Y.Z or X.Y.Z-rc.N"
if [ -n "$latest_code" ] && [ "$code" -le "$latest_code" ]; then
  die "$tag (versionCode $code) is not above $latest_tag ($latest_code). Android would refuse it as a downgrade over the current release"
fi
if gh release view "$tag" --repo "$repo" >/dev/null 2>&1 || git ls-remote --exit-code --tags origin "refs/tags/$tag" >/dev/null 2>&1; then
  die "$tag already exists on $repo. Pick a higher revision"
fi
ok "$tag, versionCode $code"

if [ "$pick" != "$revision" ]; then
  echo "  android-port.properties says $revision. It has to say $pick before the build, in a pushed commit."
  confirm "Set revision=$pick, commit and push?" || die "stopped, nothing changed"
  sed -i "s/^revision=.*/revision=$pick/" "$props"
  git add "$props"
  git commit -q -m "Android: revision $pick ($upstream)" -- "$props"
  git push -q origin master || die "push failed. The commit is local; push it, then run this again"
  ok "revision $pick committed and pushed ($(git rev-parse --short HEAD))"
fi

# ---- release notes --------------------------------------------------------------------------------
step "Release notes"
mkdir -p "$release_dir"
notes="$release_dir/release-notes-$tag.md"
marker='<!-- Write what changed above this line. Delete this line when done. -->'
if [ ! -s "$notes" ]; then
  cat >"$notes" <<EOF
### Added

-

### Fixed

-

### Changed

-

$marker
EOF
  echo "  Template written: $notes"
fi
echo "  The Notes section (checksums, install note, links) is added after the build. Empty sections are dropped."
edit_notes() {
  if command -v kate >/dev/null; then kate --block "$notes" >/dev/null 2>&1
  elif [ -n "${VISUAL:-${EDITOR:-}}" ]; then "${VISUAL:-$EDITOR}" "$notes" </dev/tty
  else nano "$notes" </dev/tty; fi
}
while true; do
  echo "  Opening the notes in an editor. Save and close it to continue."
  edit_notes
  if grep -qF "$marker" "$notes"; then warn "the template line is still there (delete it when the notes are done)"; confirm "Edit again?" && continue; die "stopped, notes not finished"; fi
  if ! grep -qE '^[[:space:]]*-[[:space:]]*[^[:space:]]' "$notes"; then warn "no bullet with any text in it"; confirm "Edit again?" && continue; die "stopped, notes empty"; fi
  break
done
grep -qE "^## $upstream-android\.$pick\b" CHANGELOG.md || warn "CHANGELOG.md has no \"## $upstream-android.$pick\" entry (the notes link to it)"
ok "notes ready"

# ---- build ----------------------------------------------------------------------------------------
step "Building (scripts/build.sh --android, asks for the keystore password)"
"$root/scripts/build.sh" --android --timeout 0 || die "the build failed (log in target/build-logs)"
apk="$root/src-tauri/gen/android/app/build/outputs/apk/universal/release/limusic-$upstream-universal-android.$pick.apk"
[ -f "$apk" ] || die "the build finished but $apk is not there"
[ "$(git rev-parse HEAD)" = "$(git rev-parse origin/master)" ] && git diff --quiet || die "the tree changed during the build"

sdk="${ANDROID_HOME:-$(conf_get ANDROID_HOME)}"
apksigner="$(ls -d "$sdk"/build-tools/*/apksigner 2>/dev/null | sort -V | tail -1)"
[ -x "$apksigner" ] || die "apksigner not found under $sdk/build-tools (ANDROID_HOME)"
cert="$("$apksigner" verify --print-certs "$apk" | sed -nE 's/^Signer #1 certificate SHA-256 digest: //p' | head -1)"
[ -n "$cert" ] || die "could not read the APK's certificate"
cert_colons="$(echo "$cert" | tr 'a-f' 'A-F' | sed 's/../&:/g; s/:$//')"
sha="$(sha256sum "$apk" | cut -d' ' -f1)"
if [ -n "$latest_tag" ]; then
  prev_cert="$(jq -r '.body // ""' <<<"$latest_json" | sed -nE 's/.*Certificate SHA-256: `([0-9A-F:]+)`.*/\1/p' | head -1)"
  # build.sh has already checked the APK against your keystore. This is the second check, against
  # what the last release told people, and only when its notes carry a whole fingerprint.
  if [[ "$prev_cert" =~ ^([0-9A-F]{2}:){31}[0-9A-F]{2}$ ]]; then
    [ "$prev_cert" = "$cert_colons" ] \
      || die "this APK's certificate ($cert_colons) is not the one $latest_tag lists ($prev_cert). An update would fail to install over it"
    ok "same signing certificate as $latest_tag"
  else
    warn "$latest_tag's notes don't list a complete certificate fingerprint${prev_cert:+ (they say $prev_cert)}; compared with your keystore only"
  fi
fi

# ---- final notes ----------------------------------------------------------------------------------
final="$release_dir/release-notes-$tag.final.md"
# Drop sections that are still the template's empty "- ".
awk '
  /^### / { if (h != "" && body ~ /[^[:space:]-]/) printf "%s%s", h, body; h = $0 "\n"; body = ""; next }
  { if (h == "") printf "%s\n", $0; else body = body $0 "\n" }
  END { if (h != "" && body ~ /[^[:space:]-]/) printf "%s%s", h, body }
' "$notes" | sed -e :a -e '/^\n*$/{$d;N;ba' -e '}' >"$final"
cat >>"$final" <<EOF

### Notes

- Install over your current version. Your data and sign-in are kept.
- Certificate SHA-256: \`$cert_colons\`
- APK SHA-256: \`$sha\`
- How the app handles your account: [SECURITY.md](https://github.com/$repo/blob/master/SECURITY.md)
- All releases: [CHANGELOG.md](https://github.com/$repo/blob/master/CHANGELOG.md)
EOF

# ---- confirm --------------------------------------------------------------------------------------
step "Ready to publish"
printf '  %-10s %s\n' Repo "https://github.com/$repo" Tag "$tag (on $(git rev-parse --short HEAD), marked Latest)" \
  APK "$name, $(du -h "$apk" | cut -f1)" SHA-256 "$sha" Notes "$final"
echo; sed 's/^/  │ /' "$final"; echo
confirm "Publish $tag to $repo now? This is public." || die "not published. The APK is at $apk"

# ---- publish: draft, upload, verify, then Latest --------------------------------------------------
step "Publishing"
upload_dir="$(mktemp -d)"; trap 'rm -rf "$upload_dir"' EXIT
cp "$apk" "$upload_dir/$name"
gh release create "$tag" "$upload_dir/$name" --repo "$repo" --target "$(git rev-parse HEAD)" \
  --title "$tag" --notes-file "$final" --draft >/dev/null || die "creating the draft release failed (nothing is public)"
ok "draft created with the APK"
mkdir "$upload_dir/check"
gh release download "$tag" --repo "$repo" --pattern "$name" --dir "$upload_dir/check" \
  || die "could not download the uploaded APK back. The draft is still private: check it on GitHub, or delete it with
    gh release delete $tag --repo $repo --yes"
[ "$(sha256sum "$upload_dir/check/$name" | cut -d' ' -f1)" = "$sha" ] \
  || die "the uploaded APK does not match the built one. The draft is still private; delete it with
    gh release delete $tag --repo $repo --yes"
ok "uploaded APK matches (SHA-256)"
gh release edit "$tag" --repo "$repo" --draft=false --latest >/dev/null \
  || die "publishing the draft failed. It is still a draft on GitHub: publish it there, or run
    gh release edit $tag --repo $repo --draft=false --latest"
[ "$(gh api "repos/$repo/releases/latest" --jq .tag_name)" = "$tag" ] || warn "GitHub does not list $tag as Latest yet; the in-app update check reads Latest"
ok "published: https://github.com/$repo/releases/tag/$tag"

cp "$apk" "$release_dir/$name"
ok "copy kept: $release_dir/$name"
