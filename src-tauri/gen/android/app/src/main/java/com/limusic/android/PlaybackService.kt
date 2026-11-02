package com.limusic.android

import android.annotation.SuppressLint
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.media.AudioAttributes as PlatformAudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.net.Uri
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Looper
import android.os.PowerManager
import androidx.annotation.OptIn
import androidx.core.content.ContextCompat
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.common.Player
import androidx.media3.common.SimpleBasePlayer
import androidx.media3.common.util.UnstableApi
import androidx.media3.session.MediaSession
import androidx.media3.session.MediaSessionService
import com.google.common.util.concurrent.Futures
import com.google.common.util.concurrent.ListenableFuture

/**
 * The media session: notification, lock screen, headset and Bluetooth buttons, Android Auto and
 * anything else that speaks MediaSession.
 *
 * The audio itself is libmpv's, driven by the Rust core, so the session's player is a
 * [SimpleBasePlayer] that only *mirrors* the Rust player ([NativeBridge.nowPlaying]) and turns
 * every transport press into a command for it. Media3 drives the foreground-service lifecycle off
 * that mirrored state: it goes foreground with the notification when playback starts, and drops
 * back when it pauses.
 *
 * Audio focus and the becoming-noisy broadcast are handled here too, because nothing else would:
 * Media3 does both only for its own ExoPlayer.
 */
@OptIn(UnstableApi::class)
class PlaybackService : MediaSessionService() {
    private var session: MediaSession? = null
    private var player: RustPlayer? = null

    override fun onCreate() {
        super.onCreate()
        val p = RustPlayer(this, mainLooper)
        val open = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        session = MediaSession.Builder(this, p).setSessionActivity(open).build()
        player = p
    }

    override fun onGetSession(controllerInfo: MediaSession.ControllerInfo): MediaSession? = session

    /**
     * Swiped out of Recents: the user closed Limusic, so it closes, playing or not. Pausing, going
     * home or switching apps never get here; only this explicit dismissal does.
     *
     * Rust pauses and saves its position first (the same save quitting the desktop app makes),
     * then the session and its notification go, the service stops, and the process ends. Ending
     * it is what makes the next launch a fresh start: the foreground service would otherwise keep
     * the process, the Rust core and the old page state alive behind the closed task. The queue
     * is in the database and comes back paused, as on the desktop.
     */
    override fun onTaskRemoved(rootIntent: Intent?) {
        NativeBridge.quit()
        session?.run {
            player.release()
            release()
        }
        session = null
        player = null
        stopForeground(android.app.Service.STOP_FOREGROUND_REMOVE)
        stopSelf()
        android.os.Process.killProcess(android.os.Process.myPid())
    }

    override fun onDestroy() {
        session?.run {
            player.release()
            release()
        }
        session = null
        player = null
        super.onDestroy()
    }
}

@OptIn(UnstableApi::class)
private class RustPlayer(private val context: Context, looper: Looper) : SimpleBasePlayer(looper) {
    private val np = NativeBridge.nowPlaying
    private val onChange: () -> Unit = { onRustState() }
    private val audio = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    private val focus = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
        .setAudioAttributes(
            PlatformAudioAttributes.Builder()
                .setUsage(PlatformAudioAttributes.USAGE_MEDIA)
                .setContentType(PlatformAudioAttributes.CONTENT_TYPE_MUSIC)
                .build(),
        )
        // Ducking is left to the system (automatic since Android 8): the music gets quieter under
        // a navigation prompt instead of stopping.
        .setWillPauseWhenDucked(false)
        .setOnAudioFocusChangeListener(::onFocusChange)
        .build()
    private var hasFocus = false
    /** Paused by a transient focus loss (a call, an assistant), so the gain resumes it. */
    private var resumeOnGain = false
    /**
     * A pause sent for a focus loss that Rust hasn't confirmed yet. Position ticks still saying
     * "playing" are from before it, and must not ask for focus again: that would take it back
     * from the app that just took it, and that app would pause instead.
     */
    private var focusPausePending = false
    private var noisyRegistered = false
    private val wake = (context.getSystemService(Context.POWER_SERVICE) as PowerManager)
        .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "limusic:playback")
        .apply { setReferenceCounted(false) }

    @Suppress("DEPRECATION") // WIFI_MODE_FULL_HIGH_PERF: the replacement (LOW_LATENCY) is for games.
    private val wifi = (context.applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager)
        .createWifiLock(WifiManager.WIFI_MODE_FULL_HIGH_PERF, "limusic:stream")
        .apply { setReferenceCounted(false) }

    /** Headphones unplugged or a Bluetooth sink gone: pause before the speaker blares. */
    private val noisy = object : BroadcastReceiver() {
        override fun onReceive(c: Context, intent: Intent) {
            if (intent.action == AudioManager.ACTION_AUDIO_BECOMING_NOISY && np.playing) {
                NativeBridge.command("pause")
            }
        }
    }

    init {
        np.addListener(onChange)
    }

    private val commands = Player.Commands.Builder()
        .addAll(
            Player.COMMAND_PLAY_PAUSE,
            Player.COMMAND_PREPARE,
            Player.COMMAND_STOP,
            Player.COMMAND_SEEK_IN_CURRENT_MEDIA_ITEM,
            Player.COMMAND_SEEK_TO_PREVIOUS,
            Player.COMMAND_SEEK_TO_PREVIOUS_MEDIA_ITEM,
            Player.COMMAND_SEEK_TO_NEXT,
            Player.COMMAND_SEEK_TO_NEXT_MEDIA_ITEM,
            Player.COMMAND_GET_CURRENT_MEDIA_ITEM,
            Player.COMMAND_GET_TIMELINE,
            Player.COMMAND_GET_METADATA,
            Player.COMMAND_GET_AUDIO_ATTRIBUTES,
            Player.COMMAND_RELEASE,
        )
        .build()

    private val attributes = AudioAttributes.Builder()
        .setUsage(C.USAGE_MEDIA)
        .setContentType(C.AUDIO_CONTENT_TYPE_MUSIC)
        .build()

    override fun getState(): State {
        val b = State.Builder()
            .setAvailableCommands(commands)
            .setAudioAttributes(attributes)
        if (!np.hasTrack) {
            return b.setPlaybackState(Player.STATE_IDLE).build()
        }
        // The display title and subtitle as well: Media3 only fills the platform's DISPLAY_TITLE /
        // DISPLAY_SUBTITLE when they are set, and system surfaces outside the notification (One UI's
        // media chip by the camera, the lock screen's Now Bar) read those first.
        val meta = MediaMetadata.Builder()
            .setTitle(np.title)
            .setDisplayTitle(np.title)
            .setArtist(np.artist)
            .setSubtitle(np.artist)
            .setAlbumTitle(np.album)
            .setArtworkUri(np.cover?.let(Uri::parse))
            .setIsPlayable(true)
            .setIsBrowsable(false)
            .build()
        val item = MediaItem.Builder().setMediaId("track-${np.generation}").setMediaMetadata(meta).build()
        val data = MediaItemData.Builder(np.generation)
            .setMediaItem(item)
            .setMediaMetadata(meta)
            .setDurationUs(if (np.durationMs > 0) np.durationMs * 1000 else C.TIME_UNSET)
            .setIsSeekable(np.durationMs > 0)
            .build()
        // A track still being resolved is buffering with play-when-ready set: from that state Media3
        // runs this service in the foreground, while the user who just pressed play is still in the
        // app. Android 12+ refuses that request from the background, so waiting for the stream
        // (seconds on a cold start) left the service out of the foreground whenever the user went
        // home at once, and the process was frozen with the music in it.
        return b.setPlaylist(listOf(data))
            .setCurrentMediaItemIndex(0)
            .setPlaybackState(if (np.loading) Player.STATE_BUFFERING else Player.STATE_READY)
            .setPlayWhenReady(np.playing || np.loading, Player.PLAY_WHEN_READY_CHANGE_REASON_USER_REQUEST)
            .setContentPositionMs { np.currentPositionMs() }
            .build()
    }

    override fun handleSetPlayWhenReady(playWhenReady: Boolean): ListenableFuture<*> {
        if (playWhenReady && !requestFocus()) {
            return Futures.immediateVoidFuture()
        }
        resumeOnGain = false
        focusPausePending = false
        np.assumePlaying(playWhenReady)
        NativeBridge.command(if (playWhenReady) "play" else "pause")
        return Futures.immediateVoidFuture()
    }

    override fun handleSeek(mediaItemIndex: Int, positionMs: Long, seekCommand: Int): ListenableFuture<*> {
        when (seekCommand) {
            Player.COMMAND_SEEK_TO_NEXT, Player.COMMAND_SEEK_TO_NEXT_MEDIA_ITEM ->
                NativeBridge.command("next")
            // Rust's previous already restarts the track when it is a few seconds in.
            Player.COMMAND_SEEK_TO_PREVIOUS, Player.COMMAND_SEEK_TO_PREVIOUS_MEDIA_ITEM ->
                NativeBridge.command("previous")
            else -> if (positionMs != C.TIME_UNSET) {
                np.assumePosition(positionMs)
                NativeBridge.command("seek", positionMs / 1000.0)
            }
        }
        return Futures.immediateVoidFuture()
    }

    override fun handleStop(): ListenableFuture<*> {
        NativeBridge.command("stop")
        return Futures.immediateVoidFuture()
    }

    override fun handlePrepare(): ListenableFuture<*> = Futures.immediateVoidFuture()

    override fun handleRelease(): ListenableFuture<*> {
        np.removeListener(onChange)
        abandonFocus()
        setPlayingResources(false)
        return Futures.immediateVoidFuture()
    }

    /** Rust's state changed (the UI, a track ending, a Listen Together host, an error). */
    private fun onRustState() {
        if (!np.playing) {
            focusPausePending = false
        } else if (!focusPausePending) {
            if (requestFocus()) {
                // Playing, and allowed to: whatever interrupted it is over, so a later regain has
                // nothing to resume.
                resumeOnGain = false
            } else {
                // Someone else holds focus that won't be shared (a phone call): don't talk over it.
                pauseForFocus()
            }
        }
        // Also while the next track is being resolved: with the screen off, the CPU and the radio
        // are what that resolving runs on.
        setPlayingResources(np.playing || np.loading)
        invalidateState()
    }

    private fun pauseForFocus() {
        if (!np.playing) return
        focusPausePending = true
        NativeBridge.command("pause")
    }

    private fun requestFocus(): Boolean {
        if (hasFocus) return true
        hasFocus = audio.requestAudioFocus(focus) == AudioManager.AUDIOFOCUS_REQUEST_GRANTED
        return hasFocus
    }

    private fun abandonFocus() {
        if (hasFocus) audio.abandonAudioFocusRequest(focus)
        hasFocus = false
    }

    private fun onFocusChange(change: Int) {
        when (change) {
            AudioManager.AUDIOFOCUS_GAIN -> {
                hasFocus = true
                focusPausePending = false
                if (resumeOnGain) {
                    resumeOnGain = false
                    NativeBridge.command("play")
                }
            }
            AudioManager.AUDIOFOCUS_LOSS_TRANSIENT -> {
                // Not ours until the regain: a play pressed meanwhile has to ask again, and is
                // refused for as long as the call (or whatever took it) lasts.
                hasFocus = false
                resumeOnGain = np.playing
                pauseForFocus()
            }
            AudioManager.AUDIOFOCUS_LOSS -> {
                // Another player took over for good; it is the user's to resume from here.
                resumeOnGain = false
                abandonFocus()
                pauseForFocus()
            }
            // AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK: the system ducks for us (see the request).
        }
    }

    /**
     * Keep the CPU and Wi-Fi up while streaming with the screen off, and listen for headphones
     * leaving. The foreground service alone keeps the process alive, not the radio.
     */
    @SuppressLint("WakelockTimeout") // Held exactly while playing or loading; released on every pause.
    private fun setPlayingResources(playing: Boolean) {
        if (playing) {
            if (!wake.isHeld) wake.acquire()
            if (!wifi.isHeld) wifi.acquire()
            if (!noisyRegistered) {
                ContextCompat.registerReceiver(
                    context,
                    noisy,
                    IntentFilter(AudioManager.ACTION_AUDIO_BECOMING_NOISY),
                    ContextCompat.RECEIVER_NOT_EXPORTED,
                )
                noisyRegistered = true
            }
        } else {
            if (wake.isHeld) wake.release()
            if (wifi.isHeld) wifi.release()
            if (noisyRegistered) {
                context.unregisterReceiver(noisy)
                noisyRegistered = false
            }
        }
    }
}
