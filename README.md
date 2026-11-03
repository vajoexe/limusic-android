<div align="center">
  <img src="./src-tauri/icons/128x128@2x.png" alt="Limusic icon" width="128">

  <h1>Limusic for Android</h1>

  <p>
    An unofficial Android port of
    <a href="https://github.com/SimoHypers/limusic">Limusic</a>,
    the YouTube Music client by SimoHypers.
  </p>

  <h2><a href="https://github.com/vajoexe/limusic-android/releases">Download</a></h2>
</div>

> **NOTICE:** Limusic needs Android System WebView **111 or newer**. With an older one the app shows a notice instead of a broken screen, and opens normally once WebView is updated. Reported issues about rendering on an outdated WebView will be ignored and closed.
>
> [How to update WebView](https://support.google.com/android/thread/103561027/an-update-regarding-app-crashes-and-system-webview?hl=en)

This is the desktop app's code running on a phone. The Rust core, the SvelteKit
interface and the libmpv playback engine are the same ones the desktop app uses.
The port adds a phone layout, a media notification, Android sign-in and the
platform glue needed for all of that to work. Wherever it could, it changes how
the app looks and leaves how it works alone.

It is a community port. It is not an official Limusic release, and the Limusic
developers do not support it. Please don't report problems with this port in
the upstream repository.

<table>
  <tr>
    <td><img src="screenshots/browse.png" alt="Home, search and an artist page on a phone"></td>
  </tr>
  <tr>
    <td><img src="screenshots/player.png" alt="The full-screen player with its lyrics and queue tabs"></td>
  </tr>
  <tr>
    <td><img src="screenshots/landscape.png" alt="The player on a phone held sideways, with the queue beside the artwork"></td>
  </tr>
  <tr>
    <td><img src="screenshots/settings.png" alt="Appearance and playback settings"></td>
  </tr>
</table>

## Status

Everything below has been tested on multiple Android VMs with multiple Android versions, and a Samsung S24 FE. Provided a semi-recent enough version of Android and WebView, everything *should* work.

What works:

- Home feed, search, artists, albums and playlists
- Playback in the background and with the screen off, with the media
  notification and media keys, lock screen controls and Bluetooth buttons
- The queue, shuffle, repeat and autoplay radio
- Synced lyrics, line by line and word by word
- Music videos, with ambient light behind them, and a fallback to audio if a
  video won't load
- Song comments: reading, liking, replying and posting
- Signing in with Google's own sign-in page, several accounts at once, and
  pasting cookies as a fallback
- Your library: likes, playlists, saved albums and artists
- Local music from a folder you pick
- Portrait and landscape, with a wider layout for tablets and desktop windows
- Samsung DeX (tested on a Galaxy S24 FE). Enable fullscreen for the app from the status bar to make theater mode fill the entire display.

What doesn't work, or works differently:

- **Speed and pitch** work, including pitch on its own, but sound a little
  rougher than on the desktop. The prebuilt libmpv this port uses has no
  Rubber Band, so time stretching uses mpv's built-in `scaletempo` instead.
- **Reverb** is missing, and so are the presets that need it. That libmpv is
  built without FFmpeg's audio filters, and reverb is made of them.
- **Loudness normalization** only turns loud tracks down. Quiet tracks stay as
  they are, and there is no limiter. The desktop version does real
  normalization, so this is a weaker substitute.
- **Discord Rich Presence** is turned off. The Discord app for Android has no
  way for another app to set your status. The only workaround uses your Discord
  login token, which breaks Discord's terms, so this port doesn't use it.
- **Sign-in** happens on Google's web sign-in page inside the app. Android's
  account picker can't be used, because it gives out a different kind of login
  than the one YouTube Music's web API accepts. If Google ever blocks the page,
  pasting cookies still works.
- **Tray, mini player window, global hotkeys, start on login and the
  self-updater** are desktop features with no Android equivalent. Instead of
  updating itself, the app tells you when a newer release is out (see
  [Updates](#updates)).
- **Samsung's Now Bar and media pill** get the title and artist of every track
  from the app, but One UI decides whether and when long titles scroll. Apps
  have no control over that, so the scrolling can look inconsistent between
  tracks.
- If Android kills the app in the background, the notification can't restart
  playback yet. Open the app again instead.

## Install

Download the APK from [Releases](https://github.com/vajoexe/limusic-android/releases)
and open it on your phone. Android will ask you to allow installs from your browser
or file manager the first time.

You need Android 8.0 or newer and Android System WebView 111 or newer. The APK
is universal: it runs natively on 64-bit ARM (`arm64-v8a`) phones and tablets
and on 64-bit x86 (`x86_64`) devices such as emulators and some Chromebooks.

### Updates

Each time it starts, the app asks GitHub for this repository's latest release.
If that release is newer than the installed one, it shows what changed and an
**Update** button that opens the Releases page. Close it with the X or by
tapping outside it, and it stays closed until the next start. **Don't show
again** turns the popup off for good. Offline, or if GitHub can't be reached,
the app starts as usual and says nothing. Nothing is downloaded or installed
for you.

Settings > Startup lists what the app does when it opens, each with its own
switch: the update check, the update popup and resuming playback. Settings >
About always shows whether an update is out. If the app hasn't asked GitHub yet
in this session, because the startup check is off or failed, it asks when
Settings opens.

The changelog in Settings > About comes from GitHub's API, which allows 60
requests an hour per network without signing in. If GitHub says no, the
changelog shows the HTTP status and why, and has a **Retry** button. Rate
limits and server errors are retried on their own, at most about once a minute
and never before GitHub's own `Retry-After` or reset time. Errors that won't go
away by waiting, such as a 404, are not retried.

Versions look like `1.4.0-rc.3-universal-android.2`: the upstream Limusic
version it is built on, then the port's own revision. Settings > About shows the
architecture running on your device in place of `universal`, for example
`1.4.0-rc.3-arm64-v8a-android.2`. It is the same release.

### Why WebView 111

The interface is a web page drawn by Android System WebView. Its colours are
CSS `oklch()` colours and its scripts are built for Chromium 111, so an older
WebView loses most colours and much of the layout. On startup the app checks
which WebView is installed. If it is older than 111, the app shows a full-screen
notice with a link to the Play Store and to
[Google's instructions](https://support.google.com/android/thread/103561027/an-update-regarding-app-crashes-and-system-webview?hl=en).
If the version can't be read, the app starts normally rather than guessing. To
update, install the latest **Android System WebView** (or Chrome, on Android
versions that use it as the WebView) from the Play Store, then reopen Limusic.

Every release is signed with the same key. Its SHA-256 certificate fingerprint is:

```
EB:14:47:0C:C1:AD:37:7A:52:6A:93:F8:75:E4:1C:16:6E:61:D0:3D:53:9B:54:61:3F:39:BE:BB:55:F7:E8:85
```

You can check a download with `apksigner verify --print-certs limusic-*.apk`. If the
fingerprint is different, the APK did not come from this repository.

## Building

Everything goes through one script:

```sh
scripts/build.sh            # menu on a terminal; Android release after 10 s
scripts/build.sh --android  # signed universal release APK (the default)
scripts/build.sh --android --debug   # debug APK for the emulator, no key needed
scripts/build.sh --linux    # Linux desktop binary
scripts/build.sh --check    # check the toolchain and the key, build nothing
scripts/build.sh --help     # every option
```

Run with no target on a terminal, it shows a menu and picks the Android release
when the countdown runs out (`--timeout SECS` or `LIMUSIC_BUILD_MENU_TIMEOUT`,
0 skips the menu). Without a terminal, in CI or a pipe, it builds Android
straight away and never waits for input.

What it does, in order:

1. **Checks the toolchain** for the target against the requirements written at
   the top of the script, and lists every mismatch with what is needed next to
   what it found. For Android: Rust 1.80 or newer with the `aarch64-linux-android`
   and `x86_64-linux-android` targets, Tauri CLI 2, Node.js 20.19 or 22.12+,
   pnpm 10, JDK 17 or 21, libclang, and the SDK's `platforms;android-37.0`,
   `build-tools;37.0.0`, `ndk;28.2.13676358` and `platform-tools`. For Linux,
   the development files of mpv, WebKitGTK 4.1, GTK 3, OpenSSL and librsvg.
2. **Offers to install** what is missing, after you answer y. It installs only
   the listed pieces: `rustup target add`, `cargo install tauri-cli`,
   `sdkmanager` for SDK packages, and `sudo pacman -S --needed` for system
   packages on Arch-based systems such as CachyOS. Elsewhere it prints what to
   install and stops. Answer no and it stops without changing anything. After
   installing it checks again and stops if anything is still wrong.
3. **Finds the signing key** (release builds only, see below).
4. **Asks for the key's password**, after the checks, so a long build never
   starts with a wrong one. A wrong password says so and asks whether to try
   again, as often as you like.
5. **Prepares the build**: sets up the SDK, NDK and JDK through
   `scripts/android/env.sh`, installs the UI dependencies only when
   `pnpm-lock.yaml` changed, and fetches libmpv only when the unpacked copy
   doesn't match the version and SHA-256 pinned in
   `scripts/android/fetch-libmpv.sh`.
6. **Builds and checks the APK**: `apksigner` verification, the signing
   certificate against your key's, an ELF check that `libapp_lib.so` and
   `libmpv.so` are there and built for each architecture, the version Gradle
   wrote into it, a size breakdown compared with the previous build, and the
   SHA-256.
7. **Cleans up** only things that can be rebuilt: Gradle's duplicate
   `app-universal-release.apk` once the named copy is verified identical, an
   old unsigned release APK, and build logs beyond the newest ten. It never
   touches the new APK, earlier releases, the keystore, your data or the
   source. It ends with a summary of the version, architectures, signature,
   size, time taken, artifact path and SHA-256.

The release APK is
`src-tauri/gen/android/app/build/outputs/apk/universal/release/limusic-<version>.apk`.
Debug builds land in `.../apk/universal/debug/`. Each run writes a log to
`target/build-logs/`, and a failed run says which step failed and keeps its log.

Optional local settings go in `~/.config/limusic/build.conf`, outside the
repository, as `KEY=value` lines: `ANDROID_HOME`, `MENU_TIMEOUT` and
`APK_BUDGET_MB`. The script reads them as plain values and never runs the file.

The version is set in one place. The upstream part is the Cargo workspace
version. The port's revision is `revision` in
[`src-tauri/android-port.properties`](src-tauri/android-port.properties). Before
each release, raise it by one, or set it back to 1 when moving to a new
upstream version. Gradle's `versionName` and `versionCode`, the About page, the
update check and the release APK's file name
(`limusic-1.4.0-rc.3-universal-android.2.apk`) all come from those two. Tag the
GitHub release `v<version>`, for example `v1.4.0-rc.3-android.2` or
`v1.4.0-rc.3-universal-android.2`, and mark it as the latest release. The update
check only looks at the latest release. Settings > About shows the notes of the
release whose tag matches the installed version, so a tag in any other format
leaves both of them blank.

### APK size

The universal release APK is about 197 MB. Release android.1 was about 96 MB
because it carried only `arm64-v8a`. Android.2 added `x86_64`, and the APK
doubled; nothing else grew. Native libraries are stored uncompressed, as Android
prefers, so the APK is roughly the sum of both architectures' libraries:

| Part | Size |
| --- | --- |
| `lib/arm64-v8a` | 98 MB |
| `lib/x86_64` | 106 MB |
| Java code and resources | 2 MB |

Most of each architecture is `libapp_lib.so`, the Rust core (about 74 MB), and
most of that is the IPADIC Japanese dictionary used to romanize lyrics (47 MB).
The libraries are already stripped. libmpv and FFmpeg add about 25 MB per
architecture. A phone only installs its own architecture's libraries, so the
installed size is about half the download.

The build script warns when a release APK grows more than 5% over the previous
build, or past `APK_BUDGET_MB` (230 by default).

### Release signing

Release APKs are signed with a self-signed certificate, which is how Android
apps outside the Play Store are normally signed. The certificate shows which key
signed the app. It says nothing about Google having checked the publisher.
Releases of this port are signed with the `vajoexe` key. Builds you make
yourself will carry your own key.

Android only installs an update over an existing app when both are signed with
the same key. So every release has to be signed with the same private key, for
as long as the app exists. If the key is lost, people have to uninstall the app,
and lose its data, before they can install a build signed with a new key.

`scripts/build.sh` looks for the key in `src-tauri/gen/android/keystore.properties`
(gitignored, holding only the keystore path and the key alias) or in
`LIMUSIC_ANDROID_STORE_FILE` and `LIMUSIC_ANDROID_KEY_ALIAS`. It never creates,
moves or replaces a key on its own:

- If a keystore exists at `~/.local/share/limusic/release.jks` but nothing
  points to it, it offers to write `keystore.properties` for it.
- If the configured keystore is missing, for example on an unmounted disk, it
  stops. A new key would not be a replacement.
- If there is no key at all, it explains why one is needed and, after two
  confirmations, runs `scripts/android/make-release-key.sh`. That creates an
  RSA 4096 key valid for 50 years. keytool asks you to choose the password, so
  pick one you will remember. `make-release-key.sh` refuses to run if a keystore
  already exists, and refuses to put one inside the repository.
  `LIMUSIC_RELEASE_KEYSTORE`, `LIMUSIC_RELEASE_ALIAS` and `LIMUSIC_RELEASE_DNAME`
  change its defaults.

The password is read from the terminal with echo off and passed to keytool and
Gradle through the environment for that one build. It never appears in
arguments, files, the log or shell history. Gradle's configuration cache is off
for the build and its daemon is stopped afterwards. In CI, set
`LIMUSIC_ANDROID_STORE_FILE`, `LIMUSIC_ANDROID_KEY_ALIAS`,
`LIMUSIC_ANDROID_STORE_PASSWORD` and `LIMUSIC_ANDROID_KEY_PASSWORD` from the CI's
secret store instead. `scripts/android/build-release.sh` still works for a
release build without the checks.

Keep the keystore out of the repository. `*.jks`, `*.keystore`, `*.p12` and
`keystore.properties` are gitignored as a safety net. Back up the keystore and
its password somewhere other than the build machine: for example the `.jks` file
attached to an entry in an encrypted password manager, plus an offline copy on
a USB drive kept apart from the password.

### Optional: a KDE launcher

This part is local to your machine and not in the repository. To start a build
from the application launcher, create
`~/.local/share/applications/limusic-build-android.desktop` with your own
checkout's path in place of `/path/to/limusic-android`:

```ini
[Desktop Entry]
Type=Application
Name=Build Android APK
Comment=Build the signed Limusic Android release APK in a terminal
Icon=/path/to/limusic-android/src-tauri/icons/128x128@2x.png
Exec=konsole --hold --workdir /path/to/limusic-android -e /path/to/limusic-android/scripts/build.sh --android
Terminal=false
Categories=Development;
```

Then run `kbuildsycoca6` so Plasma picks it up. `--hold` keeps the Konsole window
open after the build so you can read the summary. A launcher doesn't load your
shell's profile, so put `ANDROID_HOME` in `~/.config/limusic/build.conf`.

Last.fm scrobbling needs your own API key, the same as the desktop app. Put it
in `src-tauri/lastfm.keys`:

```
LIMUSIC_LASTFM_API_KEY=your_key
LIMUSIC_LASTFM_API_SECRET=your_secret
```

The desktop build is unchanged. See [docs/BUILD-PLATFORMS.md](docs/BUILD-PLATFORMS.md)
and the [upstream README](https://github.com/SimoHypers/limusic#readme) for
Linux, Windows and macOS.

## Credits

Limusic was created by [SimoHypers](https://github.com/SimoHypers) and the
Limusic contributors. Nearly all of this app is their work. This port only adds
the Android pieces.

If you'd like to support the original developers, you can do so at
[ko-fi.com/simohypers](https://ko-fi.com/simohypers). That money goes to them,
not to this port.

Playback uses [mpv](https://mpv.io) and [FFmpeg](https://ffmpeg.org), packaged
for Android by [libmpv-android](https://github.com/jarnedemeulemeester/libmpv-android).
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) lists everything that ships
inside the APK.

## License

GPL-3.0-or-later, the same as Limusic. See [LICENSE](LICENSE). The changes made
for this port are described in [NOTICE](NOTICE).

The APK includes a GPL build of FFmpeg, which is why the app as a whole is
distributed under GPL version 3. Anyone who distributes the APK has to make the
matching source code available too. This repository is that source for the app.
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) has links to the source of
the bundled libraries.

## Disclaimer

This project is not affiliated with, funded, authorized or endorsed by YouTube,
Google LLC or any of their affiliates. It is also not an official release from
the Limusic project. All trademarks belong to their respective owners.
