#!/usr/bin/env bash
# Render the Android launcher icons from Limusic's own logo (ui/src/lib/assets/favicon.svg, the
# vector the desktop icons in src-tauri/icons were made from). `tauri icon` would also rewrite every
# desktop icon, so the Android set is drawn here instead.
#
#   scripts/android/make-icons.sh        (needs rsvg-convert and ImageMagick 7)
#
# Writes into src-tauri/gen/android/app/src/main/res:
#   mipmap-*/ic_launcher_foreground.png    adaptive foreground, 108dp, logo inside the 66dp safe zone
#   mipmap-*/ic_launcher_monochrome.png    the same shape in white, for Android 13+ themed icons
#   mipmap-*/ic_launcher{,_round}.png      legacy icons (API < 26): the logo on the background
#   mipmap-anydpi-v26/ic_launcher{,_round}.xml, values/ic_launcher_background.xml
set -euo pipefail
cd "$(dirname "$0")/../.."
SVG=ui/src/lib/assets/favicon.svg
RES=src-tauri/gen/android/app/src/main/res
BG='#141217' # the app's dark background, close to `--background` in ui/src/routes/layout.css
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# density, adaptive canvas px (108dp), legacy px (48dp)
for d in "mdpi 108 48" "hdpi 162 72" "xhdpi 216 96" "xxhdpi 324 144" "xxxhdpi 432 192"; do
	set -- $d
	out=$RES/mipmap-$1
	mkdir -p "$out"
	# The drawing fills ~86% of its 200px viewBox; at 58% of the canvas it spans ~50%, well inside
	# the 66dp circle a launcher mask always keeps, with a margin for squircles and other shapes.
	logo=$(( $2 * 58 / 100 ))
	rsvg-convert -w "$logo" -h "$logo" "$SVG" -o "$TMP/logo.png"
	magick -size "${2}x${2}" xc:none "$TMP/logo.png" -gravity center -composite \
		"PNG32:$out/ic_launcher_foreground.png"
	magick "$out/ic_launcher_foreground.png" -fill white -colorize 100 \
		"PNG32:$out/ic_launcher_monochrome.png"
	# Legacy: logo at ~66% on a rounded square / a circle.
	l=$(( $3 * 66 / 100 ))
	r=$(( $3 / 5 ))
	rsvg-convert -w "$l" -h "$l" "$SVG" -o "$TMP/legacy.png"
	magick -size "${3}x${3}" xc:none -fill "$BG" \
		-draw "roundrectangle 0,0 $(( $3 - 1 )),$(( $3 - 1 )) $r,$r" \
		"$TMP/legacy.png" -gravity center -composite "PNG32:$out/ic_launcher.png"
	magick -size "${3}x${3}" xc:none -fill "$BG" \
		-draw "circle $(( $3 / 2 )),$(( $3 / 2 )) $(( $3 / 2 )),0" \
		"$TMP/legacy.png" -gravity center -composite "PNG32:$out/ic_launcher_round.png"
done

mkdir -p "$RES/mipmap-anydpi-v26" "$RES/values"
for name in ic_launcher ic_launcher_round; do
	cat > "$RES/mipmap-anydpi-v26/$name.xml" <<'XML'
<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/ic_launcher_background" />
    <foreground android:drawable="@mipmap/ic_launcher_foreground" />
    <monochrome android:drawable="@mipmap/ic_launcher_monochrome" />
</adaptive-icon>
XML
done
cat > "$RES/values/ic_launcher_background.xml" <<XML
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="ic_launcher_background">$BG</color>
</resources>
XML
echo "launcher icons written to $RES"
