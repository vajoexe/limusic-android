# Changelog

Releases of the Android port. Versions are the upstream Limusic version
followed by the port's own revision. Downloads are on the
[Releases](https://github.com/vajoexe/limusic-android/releases) page.

Every release is signed with the same key, certificate SHA-256
`EB:14:47:0C:C1:AD:37:7A:52:6A:93:F8:75:E4:1C:16:6E:61:D0:3D:53:9B:54:61:3F:39:BE:BB:55:F7:E8:85`.

## 1.4.0-rc.4-android.2

### Added

- Touch and hold a song, a song in the queue or a card to open its menu, the
  same one the ⋯ button opens. The menu opens right where your thumb is.
- "Open the player when you press play" in Settings > Appearance > Player view,
  for anyone who liked the full player opening by itself.

### Changed

- Playing a song starts it in the bar at the bottom of the screen instead of
  opening the full player. Tap the bar to open the player.
- Song rows no longer show a ⋯ button on every row. Touch and hold the song
  instead. TalkBack and a keyboard still reach the button.

### Fixed

- Tapping a card or a row no longer presses buttons you can't see. Play, menu
  and Subscribe buttons that only show up under a mouse took taps on the phone
  too, so a tap on the corner of an artist card could subscribe to it.
- The remove button on Home shortcuts and the Listen Together host buttons are
  always shown on the phone, where they used to be invisible.
- Touch and hold on a song no longer selects its title and brings up the copy
  bar.

## 1.4.0-rc.4-android.1

Now built on Limusic 1.4.0-rc.4.

### Added

- Material You theme, in Settings > Appearance. On a phone it brings its colors,
  font and a wavy progress bar in the player. Tablets and DeX also get its
  restyled sidebar and player bar.
- Enhanced Lyrics, a card in Settings > Appearance that animates the lyrics as
  they're sung. It also works for lyrics that are only timed by line.
- Unison as a lyrics source, with a button to rate the lyrics it found.
- "Prefer word-by-word lyrics" in Settings, for when a source has both kinds.
- Share links can start at a time: tick "Start at" in the Share dialog. A link
  with a time opened through Open link starts playing there.
- Timecodes in comments, like 2:54, are tappable and jump to that point.
- Tapping Search in the bottom bar while you're already on Search puts the cursor
  back in the search field.

### Fixed

- Back and Forward bring back your earlier searches, results included.
- Picking a category while you type keeps what you've typed, and a category
  picked while a search is still loading no longer goes back to the old one.
- A song removed from the queue while shuffling stays removed when you turn
  shuffle off.
- The radio of a music video no longer comes up empty when Hide videos is on.
- Playback no longer stops when one of YouTube's fallback servers fails in a
  particular way.
- The search page no longer empties when the app switches between its phone and
  tablet layouts, for example when you unfold a foldable or resize the window in
  split screen or DeX.

### Changed

- SimpMusic is gone from the lyrics sources. Its server no longer answers other
  apps.
- New and updated translations.

## 1.4.0-rc.3-android.4

### Fixed

- The home feed sometimes failed to load at startup, and some controls stopped
  responding until the app was restarted. It happened most on a busy phone.
- Tempo and pitch now work on Android. A speed change keeps the pitch, and a
  pitch shift keeps the tempo.
- The changelog in Settings recovers on its own when GitHub is busy or rate
  limited. It says when you're offline and has a Retry button.

### Changed

- The update notice shows more of the release notes, and fades at the edge
  instead of cutting a line in half.
- The update notice has a "Don't show again" button. Settings > Startup turns it
  back on, and can also switch the update check off completely.
- Reverb isn't available on Android yet, so it's hidden there. Slowed and
  Nightcore still change tempo and pitch.

### Privacy

- After you sign in, the app clears the Google session from its sign-in page and
  keeps only what YouTube Music needs. The next sign-in asks Google again.
- A pasted cookie is cleared from the clipboard once sign-in succeeds.
- Removing an account now wipes its session from the app's database on disk, not
  just from the list.

APK SHA-256: `a587a3c868c3b6e5df7b3ff9f6c595e20eb29025b7c682b8cf2d0db330233b14`

## 1.4.0-rc.3-android.3

### Added

- The app checks for a new release each time it starts. If one is out, it shows
  what changed and an Update button that opens the Releases page. Close it with
  the X or by tapping outside it. Offline, it stays quiet.
- Settings > About shows the version and the architecture it is running on, for
  example `1.4.0-rc.3-arm64-v8a-android.3`.

### Fixed

- Playback no longer goes silent when you start a song and go straight to the
  home screen. It happened most often right after opening the app, and with
  Bluetooth audio.
- Playing with no connection no longer leaves the notification stuck loading. It
  now shows the track as paused.
- Samsung's media pill and Now Bar no longer see each track change twice.
- The Bug Report link in Settings opens this repository's Issues page instead of
  a page that doesn't exist.

### Changed

- Settings > About shows only this release's notes.
- Version names now follow `<upstream>-universal-android.<revision>`. The APK is
  still a single universal file for arm64-v8a and x86_64.

APK SHA-256: `b58f9cef0dbddb97bd1563ff17af4ca493437bdfeb381fe506196bd3ad039ce6`

## 1.4.0-rc.3-android.2

One APK for all supported devices. It runs natively on both 64-bit ARM phones
and tablets (`arm64-v8a`) and x86_64 devices such as emulators and some
Chromebooks (`x86_64`).

### Fixed

- The bottom navigation and mini player come back after hiding the keyboard
  while a text field is still selected.
- Search suggestions stay above the keyboard and inside the screen, and picking
  one closes the keyboard.
- Manual lyrics search ("Wrong song? Search by title") can be typed in again, in
  portrait and landscape. In landscape the form fits in one row above the
  keyboard.
- No more dark outline around the rounded corners of light-coloured music
  videos.
- In landscape, the ambient light follows the video when the controls show and
  hide.

### Changed

- WebView 111 or newer is now required. On an older Android System WebView, the
  app shows a notice with an update link instead of a broken screen. It opens
  normally once WebView is updated.
- Removing an account also signs that account out of the in-app Google sign-in
  page.
- The song title and artist are passed more explicitly to Samsung's Now Bar and
  the media pill by the camera.
- Lock screen controls, Bluetooth buttons and Samsung DeX are confirmed working.

APK SHA-256: `4026a390e34e4ce732c4c5141d02c4fba2fc107244f68b2858adef4700c58616`

## 1.4.0-rc.3-android.1

The first stable release.
