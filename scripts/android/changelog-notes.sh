#!/usr/bin/env bash
# Print one CHANGELOG.md entry as GitHub release notes, for publish.sh to start the notes from.
#
#   scripts/android/changelog-notes.sh 1.4.0-rc.4-android.2 [CHANGELOG.md]
#
# The entry is everything under "## <version>" up to the next "## ". The changelog wraps its lines
# at 80 columns; a release page shows every line break, so each paragraph and list item is joined
# back into one line. Headings, blank lines and list items stay as they are. Prints nothing and
# exits 1 when there is no such entry.
set -euo pipefail

version="${1:?usage: changelog-notes.sh <version> [CHANGELOG.md]}"
file="${2:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/CHANGELOG.md}"

out="$(awk -v h="## $version" '
  function flush() { if (cur != "") print cur; cur = "" }
  !on { if ($0 == h || index($0, h " ") == 1) on = 1; next }
  /^## / { exit }
  /^[[:space:]]*$/ { flush(); print ""; next }
  /^#/ || /^[-*] / || /^[0-9]+\. / { flush(); cur = $0; next }
  {
    line = $0; sub(/^[[:space:]]+/, "", line)
    cur = (cur == "") ? line : cur " " line
  }
  END { flush() }
' "$file" | sed -e '/./,$!d' | sed -e :a -e '/^\n*$/{$d;N;ba' -e '}')"

[ -n "$out" ] || exit 1
printf '%s\n' "$out"
