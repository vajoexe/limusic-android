# Security

## Reporting a problem

If you find a security problem in this Android port, please open a
[private security advisory](https://github.com/vajoexe/limusic-android/security/advisories/new)
instead of a public issue. Problems in the desktop app go to
[upstream](https://github.com/SimoHypers/limusic).

## How the Android app handles your account

**Signing in.** "Sign in with Google" opens Google's own sign-in page
(accounts.google.com) in a separate screen. The page runs in a WebView with its
normal user agent, and the line under the title always shows which site you are
on. You type your password into Google's page; the app never sees it. When the
page lands on music.youtube.com, the app reads that site's cookies, checks them
against YouTube Music, and keeps them only if the check passes. Pasting a
session cookie by hand still works as a fallback.

**What is stored.** The YouTube Music session cookies of each saved account are
kept in the app's database, in the app's private storage. Other apps can't read
it, and Android's file-based encryption keeps it unreadable on disk until the
phone is first unlocked after a restart. The app does not add its own
encryption on top. Backups are off: neither Google's cloud backup,
nor device-to-device transfer, nor `adb backup` copies the app's data.

**The sign-in screen's own session.** The sign-in screen keeps Google's web
session in a WebView profile of its own, separate from the rest of the app, so
signing in again later doesn't always ask for your password. Removing an
account from Limusic also clears that session. Signing out keeps it, the same
way the desktop app does.

**Logs and bug reports.** Cookies, tokens and passwords are never written to
the log. "Open the bug form" fills in a summary with cookies, tokens, signed
URLs, file paths and IP addresses removed.

**Network.** Release builds only allow encrypted connections, except to the
phone itself (127.0.0.1): music videos and audio pass through a small local
proxy inside the app. Each proxy needs a random secret in the address that
changes on every launch, and only serves streams the app itself asked for, so
other apps on the phone can't use it.

**Things to know.**

- Anyone who can unlock your phone and open Limusic can use your YouTube
  Music account in it, the same as in any other app you are signed in to.
- Any app on the phone can see what is playing and control playback through
  Android's media controls. Bluetooth, the lock screen and Android Auto work
  that way, so it can't be limited.
- Signing in through Google's page is up to Google. If it refuses, use the
  cookie paste instead.
