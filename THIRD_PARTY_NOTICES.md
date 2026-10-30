# Third-party software in the Android APK

The Android APK bundles native libraries that this repository doesn't build
itself. They come prebuilt from the `dev.jdtech.mpv:libmpv` package, version
1.0.0, on Maven Central. `scripts/android/fetch-libmpv.sh` downloads it and
checks it against a pinned SHA-256.

## Native libraries

| Library | Files in the APK | License | Source |
|---|---|---|---|
| libmpv-android 1.0.0 (packaging) | (the build) | MIT | https://github.com/jarnedemeulemeester/libmpv-android |
| mpv 0.41.0 | `libmpv.so` | GPL-2.0-or-later as built here (mpv is LGPL-2.1-or-later only without GPL parts) | https://github.com/mpv-player/mpv |
| FFmpeg | `libavcodec.so`, `libavdevice.so`, `libavfilter.so`, `libavformat.so`, `libavutil.so`, `libswresample.so`, `libswscale.so` | GPL-3.0-or-later (built with `--enable-gpl --enable-version3`) | https://ffmpeg.org/download.html |
| LLVM libc++ | `libc++_shared.so` | Apache-2.0 WITH LLVM-exception | https://github.com/llvm/llvm-project |

The build scripts that produce these libraries are those of mpv-android
(https://github.com/mpv-android/mpv-android, `buildscripts/`), which
libmpv-android builds from.

The following libraries are linked into the files above. This list was read
from the binaries (FFmpeg's configure flags and strings inside `libmpv.so`), so
it may be incomplete:

| Library | License | Source |
|---|---|---|
| Mbed TLS | Apache-2.0 or GPL-2.0-or-later | https://github.com/Mbed-TLS/mbedtls |
| dav1d | BSD-2-Clause | https://code.videolan.org/videolan/dav1d |
| libxml2 | MIT | https://gitlab.gnome.org/GNOME/libxml2 |
| libass | ISC | https://github.com/libass/libass |
| HarfBuzz | MIT | https://github.com/harfbuzz/harfbuzz |
| libplacebo | LGPL-2.1-or-later | https://code.videolan.org/videolan/libplacebo |
| Lua 5.2 | MIT | https://www.lua.org |

libass normally also pulls in FreeType (FreeType License or GPL-2.0-or-later)
and FriBidi (LGPL-2.1-or-later).

## Java and Kotlin libraries

AndroidX (Media3, AppCompat, Activity, Lifecycle and WebKit), Material
Components for Android and the Kotlin standard library are Apache-2.0. The
versions are declared in `src-tauri/gen/android/app/build.gradle.kts`.

## Rust and JavaScript dependencies

The Rust crates are listed in `Cargo.lock` and the JavaScript packages in
`ui/pnpm-lock.yaml`. Most use MIT, Apache-2.0 or similar licenses. A full
generated list (for example with `cargo about`) is not included yet.

## Why the whole app is GPL-3.0

The FFmpeg build above is GPL-3.0-or-later, so the APK as a whole is
distributed under GPL version 3. Limusic itself is GPL-3.0-or-later, so the
two are compatible. Anyone who distributes the APK has to make the source of
all of the above available along with it: this repository for the app, and the
links above for the libraries.
