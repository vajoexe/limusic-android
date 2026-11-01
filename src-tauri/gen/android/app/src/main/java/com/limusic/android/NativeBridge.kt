package com.limusic.android

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.provider.OpenableColumns
import android.provider.Settings
import android.util.Log
import java.lang.ref.WeakReference

/**
 * The JNI seam with the Rust core (src-tauri/src/android.rs).
 *
 * Rust calls the `@JvmStatic` methods below from its own threads (the media-controls thread, tokio
 * workers); every one of them hops to the main thread before touching Android state. Kotlin calls
 * back through the two `external` functions. Nothing here goes through the webview, so the media
 * session keeps working while the activity is stopped or gone.
 */
object NativeBridge {
    private const val TAG = "limusic"

    init {
        // The Rust library; idempotent, and Tauri's activity loads the same one.
        System.loadLibrary("app_lib")
    }

    private val main = Handler(Looper.getMainLooper())
    private var activity: WeakReference<Activity> = WeakReference(null)
    private lateinit var appContext: Context

    /** What the media session shows. Main thread only. */
    val nowPlaying = NowPlaying()

    /** Hand Rust the JVM (for libavcodec/mpv's AudioTrack output) and remember the activity. */
    fun attach(activity: Activity) {
        this.activity = WeakReference(activity)
        if (!::appContext.isInitialized) {
            appContext = activity.applicationContext
            nativeAttach(appContext)
        }
    }

    /** A transport command for the Rust player: play, pause, toggle, next, previous, stop, seek. */
    fun command(cmd: String, arg: Double = 0.0) {
        try {
            nativeMediaCommand(cmd, arg)
        } catch (e: UnsatisfiedLinkError) {
            Log.w(TAG, "media command before the native library loaded: $cmd", e)
        }
    }

    /** System bar / cutout / IME insets in CSS pixels, for the page's safe area, and the on-screen
     *  keyboard's own height (0 while it is hidden), which `bottom` already includes. */
    fun insets(top: Float, right: Float, bottom: Float, left: Float, keyboard: Float) {
        try {
            nativeInsets(top, right, bottom, left, keyboard)
        } catch (e: UnsatisfiedLinkError) {
            Log.w(TAG, "insets before the native library loaded", e)
        }
    }

    /** Swiped out of Recents: Rust pauses and saves its position (`android::nativeQuit`). */
    fun quit() {
        try {
            nativeQuit()
        } catch (e: UnsatisfiedLinkError) {
            Log.w(TAG, "quit before the native library loaded", e)
        }
    }

    /** How the folder pick ended: `picked` with a path, `cancelled`, `denied`, `unsupported`. */
    fun folderPicked(status: String, path: String?) {
        try {
            nativeFolderPicked(status, path)
        } catch (e: UnsatisfiedLinkError) {
            Log.w(TAG, "folder pick before the native library loaded", e)
        }
    }

    /** Whether the audio-files permission is held, reported on every resume. */
    fun audioAccess(granted: Boolean) {
        try {
            nativeAudioAccess(granted)
        } catch (e: UnsatisfiedLinkError) {
            Log.w(TAG, "audio access before the native library loaded", e)
        }
    }

    /** The music.youtube.com `Cookie` header SignInActivity ended with. A credential: never log. */
    fun signInCookie(cookie: String) {
        try {
            nativeSignInCookie(cookie)
        } catch (e: UnsatisfiedLinkError) {
            Log.w(TAG, "sign-in before the native library loaded", e)
            SignInActivity.finished(false, null)
        }
    }

    @JvmStatic private external fun nativeAttach(context: Context)
    @JvmStatic private external fun nativeMediaCommand(cmd: String, arg: Double)
    @JvmStatic private external fun nativeInsets(
        top: Float,
        right: Float,
        bottom: Float,
        left: Float,
        keyboard: Float,
    )
    @JvmStatic private external fun nativeSignInCookie(cookie: String)
    @JvmStatic private external fun nativeFolderPicked(status: String, path: String?)
    @JvmStatic private external fun nativeAudioAccess(granted: Boolean)
    @JvmStatic private external fun nativeQuit()

    // --- called from Rust ----------------------------------------------------------------------

    @JvmStatic
    fun mediaMetadata(title: String, artist: String, album: String?, cover: String?) {
        main.post { nowPlaying.setTrack(title, artist, album, cover) }
    }

    @JvmStatic
    fun mediaAlbum(album: String) {
        main.post { nowPlaying.setAlbum(album) }
    }

    @JvmStatic
    fun mediaDuration(secs: Double) {
        main.post { nowPlaying.setDuration(secs) }
    }

    @JvmStatic
    fun mediaPlayback(playing: Boolean, posSecs: Double) {
        main.post { nowPlaying.setPlayback(playing, posSecs) }
    }

    @JvmStatic
    fun mediaClear() {
        main.post { nowPlaying.clear() }
    }

    @JvmStatic
    fun setImmersive(on: Boolean) {
        main.post {
            // MainActivity (the only one `attach`ed) also hides the bars on its own (a phone on its
            // side), and has to know theater wants them hidden so a rotation or a resume doesn't
            // bring them back.
            val a = activity.get()?.takeUnless { it.isFinishing || it.isDestroyed } ?: return@post
            (a as? MainActivity)?.setTheaterFullscreen(on)
        }
    }

    /** Local music's "Add folder": permission first, then the system folder picker. */
    @JvmStatic
    fun pickFolder() {
        main.post {
            val a = activity.get()?.takeUnless { it.isFinishing || it.isDestroyed } as? MainActivity
            if (a == null) folderPicked("cancelled", null) else a.pickFolder()
        }
    }

    @JvmStatic
    fun openAppSettings() {
        main.post {
            val intent = Intent(
                Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                Uri.fromParts("package", appContext.packageName, null),
            ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            try {
                (activity.get() ?: appContext).startActivity(intent)
            } catch (e: Exception) {
                Log.w(TAG, "no settings screen for this app", e)
            }
        }
    }

    /** A document the system picker handed over (`content://…`), opened for Rust as a plain file
     *  descriptor it then owns: "r" to read, "wt" to write from the start. -1 when it can't be. */
    @JvmStatic
    fun openContent(uri: String, mode: String): Int =
        try {
            appContext.contentResolver.openFileDescriptor(Uri.parse(uri), mode)?.detachFd() ?: -1
        } catch (e: Exception) {
            Log.w(TAG, "picked document not opened", e)
            -1
        }

    /** That document's file name as the picker showed it, which its URI does not carry. */
    @JvmStatic
    fun contentName(uri: String): String? =
        try {
            appContext.contentResolver
                .query(Uri.parse(uri), arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
                ?.use { if (it.moveToFirst()) it.getString(0) else null }
        } catch (e: Exception) {
            null
        }

    @JvmStatic
    fun openSignIn(addAccount: Boolean) {
        main.post {
            val from = activity.get()?.takeUnless { it.isFinishing || it.isDestroyed }
            val intent = Intent(from ?: appContext, SignInActivity::class.java)
                .putExtra(SignInActivity.EXTRA_ADD_ACCOUNT, addAccount)
            if (from == null) intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            (from ?: appContext).startActivity(intent)
        }
    }

    @JvmStatic
    fun forgetSignIn() {
        main.post { SignInActivity.forget() }
    }

    @JvmStatic
    fun signInFinished(ok: Boolean, message: String?) {
        main.post { SignInActivity.finished(ok, message) }
    }

    @JvmStatic
    fun openUrl(url: String) {
        main.post {
            val uri = Uri.parse(url)
            if (uri.scheme != "http" && uri.scheme != "https") return@post
            val intent = Intent(Intent.ACTION_VIEW, uri).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            try {
                (activity.get() ?: appContext).startActivity(intent)
            } catch (e: Exception) {
                Log.w(TAG, "no app can open this link", e)
            }
        }
    }
}

/**
 * The current track as Rust last described it, plus who wants to hear about changes. Positions
 * are listening seconds (already divided by the tempo on the Rust side), so the session can
 * extrapolate at 1x.
 */
class NowPlaying {
    var generation = 0L
        private set
    var title: String? = null
        private set
    var artist: String? = null
        private set
    var album: String? = null
        private set
    var cover: String? = null
        private set
    var durationMs: Long = -1
        private set
    var playing = false
        private set
    private var positionMs = 0L
    /** `elapsedRealtime` when [positionMs] was true. */
    private var positionAt = 0L

    private val listeners = mutableListOf<() -> Unit>()

    fun addListener(l: () -> Unit) = listeners.add(l)
    fun removeListener(l: () -> Unit) = listeners.remove(l)
    private fun changed() = listeners.toList().forEach { it() }

    val hasTrack get() = title != null

    fun setTrack(title: String, artist: String, album: String?, cover: String?) {
        generation++
        this.title = title
        this.artist = artist
        this.album = album
        this.cover = cover
        durationMs = -1
        positionMs = 0
        positionAt = SystemClock.elapsedRealtime()
        changed()
    }

    /** No track any more (the mini player's session was dismissed). */
    fun clear() {
        generation++
        title = null
        artist = null
        album = null
        cover = null
        durationMs = -1
        playing = false
        positionMs = 0
        positionAt = SystemClock.elapsedRealtime()
        changed()
    }

    fun setAlbum(album: String) {
        this.album = album
        changed()
    }

    fun setDuration(secs: Double) {
        durationMs = if (secs.isFinite() && secs > 0) (secs * 1000).toLong() else -1
        changed()
    }

    fun setPlayback(playing: Boolean, posSecs: Double) {
        this.playing = playing
        positionMs = if (posSecs.isFinite() && posSecs > 0) (posSecs * 1000).toLong() else 0
        positionAt = SystemClock.elapsedRealtime()
        changed()
    }

    /** Where playback is now: the last reported position, run forward at 1x while playing. */
    fun currentPositionMs(): Long {
        val p = if (playing) positionMs + (SystemClock.elapsedRealtime() - positionAt) else positionMs
        return if (durationMs > 0) p.coerceIn(0, durationMs) else p.coerceAtLeast(0)
    }

    /** The session's own guess while a command is in flight to Rust, so its UI doesn't flicker. */
    fun assumePlaying(playing: Boolean) {
        positionMs = currentPositionMs()
        positionAt = SystemClock.elapsedRealtime()
        this.playing = playing
    }

    fun assumePosition(ms: Long) {
        positionMs = ms.coerceAtLeast(0)
        positionAt = SystemClock.elapsedRealtime()
    }
}
