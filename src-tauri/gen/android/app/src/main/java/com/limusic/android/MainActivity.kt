package com.limusic.android

import android.Manifest
import android.content.ComponentName
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.provider.DocumentsContract
import android.view.WindowManager
import android.net.Uri
import android.webkit.WebView
import java.io.File
import androidx.activity.OnBackPressedCallback
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.ActivityResultLauncher
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.content.ContextCompat
import androidx.core.view.ViewCompat
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import androidx.media3.session.MediaController
import androidx.media3.session.SessionToken
import com.google.common.util.concurrent.ListenableFuture

class MainActivity : TauriActivity() {
  private var controller: ListenableFuture<MediaController>? = null
  private var webView: WebView? = null
  /** Theater mode asked for full screen (NativeBridge.setImmersive), on top of `immersive()`. */
  private var theaterFullscreen = false
  /** Theater mode took a desktop window full screen (`requestFullscreenMode`), to undo on exit. */
  private var windowFullscreen = false
  private lateinit var folderPicker: ActivityResultLauncher<Uri?>
  private lateinit var audioPermission: ActivityResultLauncher<String>

  /** A phone on its side, full screen and not in a window of its own (split screen, DeX, a
   *  tablet): the status and navigation bars hide, a swipe from an edge brings them back for a
   *  moment, and the page draws behind the camera cutout too. */
  private fun immersive(config: Configuration = resources.configuration): Boolean =
    config.orientation == Configuration.ORIENTATION_LANDSCAPE &&
      config.smallestScreenWidthDp < 600 &&
      !isInMultiWindowMode

  private fun applyImmersive() {
    val bars = WindowCompat.getInsetsController(window, window.decorView)
    if (immersive() || theaterFullscreen) {
      bars.systemBarsBehavior = WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
      bars.hide(WindowInsetsCompat.Type.systemBars())
    } else {
      bars.show(WindowInsetsCompat.Type.systemBars())
    }
    webView?.let { ViewCompat.requestApplyInsets(it) }
  }

  // A refusal (not a desktop window after all, or the system declined) leaves theater in the
  // window, which is still usable: logged, and not retried.
  private fun fullscreenOutcome(step: String) =
    object : android.os.OutcomeReceiver<Void, Throwable> {
      override fun onResult(result: Void?) {}
      override fun onError(error: Throwable) {
        if (step == "enter") windowFullscreen = false
        android.util.Log.w("Limusic", "theater full screen ($step) refused: ${error.message}")
      }
    }

  fun setTheaterFullscreen(on: Boolean) {
    theaterFullscreen = on
    applyImmersive()
    // In a desktop window (DeX, desktop windowing) hiding the bars leaves the window its size, so
    // theater mode asks for the whole display the way the desktop app does, and gives it back.
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.VANILLA_ICE_CREAM) {
      if (on && isInMultiWindowMode && !windowFullscreen) {
        windowFullscreen = true
        requestFullscreenMode(FULLSCREEN_MODE_REQUEST_ENTER, fullscreenOutcome("enter"))
      } else if (!on && windowFullscreen) {
        windowFullscreen = false
        requestFullscreenMode(FULLSCREEN_MODE_REQUEST_EXIT, fullscreenOutcome("exit"))
      }
    }
  }

  // Local music. The scanner and mpv read files by path, so the folder comes from the system picker
  // and is turned into one; the audio-files permission is what lets a path under shared storage be
  // read (Android shows an app the media types it was granted).
  private val audioPermissionName =
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
      Manifest.permission.READ_MEDIA_AUDIO
    } else {
      Manifest.permission.READ_EXTERNAL_STORAGE
    }

  private fun hasAudioAccess() =
    ContextCompat.checkSelfPermission(this, audioPermissionName) == PackageManager.PERMISSION_GRANTED

  fun pickFolder() {
    if (hasAudioAccess()) folderPicker.launch(null) else audioPermission.launch(audioPermissionName)
  }

  /** `primary:Music/Albums` → /storage/emulated/0/Music/Albums; an SD card's `1A2B-3C4D:Music` →
   *  /storage/1A2B-3C4D/Music. Anything that isn't a storage volume has no path. */
  private fun treePath(uri: Uri): String? {
    if (uri.authority != "com.android.externalstorage.documents") return null
    val id = DocumentsContract.getTreeDocumentId(uri)
    val volume = id.substringBefore(':')
    val rel = id.substringAfter(':', "")
    val root = if (volume == "primary") {
      Environment.getExternalStorageDirectory().path
    } else {
      "/storage/$volume"
    }
    val dir = if (rel.isEmpty()) File(root) else File(root, rel)
    return dir.path.takeIf { dir.isDirectory }
  }

  override fun onCreate(savedInstanceState: Bundle?) {
    enableEdgeToEdge()
    // Before super: that is where the Tauri runtime (and with it the player) starts, and mpv's
    // audio output needs the JVM from the first track on.
    NativeBridge.attach(this)
    super.onCreate(savedInstanceState)
    // A WebView too old to draw the app (or none at all): a native notice over it, before this
    // activity is ever shown.
    WebViewNoticeActivity.takeOver(this)
    // Into the cutout on every edge (targetSdk 35+ already lays out there, this says so for
    // older releases too); `immersive` is when the page is told it may use that room.
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
      window.attributes.layoutInDisplayCutoutMode =
        WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_ALWAYS
    } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
      window.attributes.layoutInDisplayCutoutMode =
        WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
    }
    applyImmersive()
    folderPicker = registerForActivityResult(ActivityResultContracts.OpenDocumentTree()) { uri ->
      if (uri == null) return@registerForActivityResult NativeBridge.folderPicked("cancelled", null)
      val path = treePath(uri)
      NativeBridge.folderPicked(if (path == null) "unsupported" else "picked", path)
    }
    audioPermission = registerForActivityResult(ActivityResultContracts.RequestPermission()) { ok ->
      NativeBridge.audioAccess(ok)
      if (ok) folderPicker.launch(null) else NativeBridge.folderPicked("denied", null)
    }
    // Registered before the webview's own back handler, so it only runs once the SPA has no
    // history left to go back through: then the app goes to the background like any music
    // player, instead of finishing and stopping the music with it.
    onBackPressedDispatcher.addCallback(this, object : OnBackPressedCallback(true) {
      override fun handleOnBackPressed() {
        moveTaskToBack(true)
      }
    })
  }

  override fun onWebViewCreate(webView: WebView) {
    // Edge to edge (mandatory at targetSdk 35+): the page draws under the system bars, so it has
    // to be told where they are. The IME counts as the bottom bar while it is open, so a focused
    // field is never under the keyboard. Immersive, hidden bars report nothing, and the cutout
    // is left out on purpose: the page uses the whole screen, the camera hole included.
    this.webView = webView
    ViewCompat.setOnApplyWindowInsetsListener(webView) { v, insets ->
      val bars = insets.getInsets(
        if (immersive()) {
          WindowInsetsCompat.Type.systemBars()
        } else {
          WindowInsetsCompat.Type.systemBars() or WindowInsetsCompat.Type.displayCutout()
        },
      )
      val ime = insets.getInsets(WindowInsetsCompat.Type.ime())
      val d = v.resources.displayMetrics.density
      NativeBridge.insets(
        bars.top / d,
        bars.right / d,
        maxOf(bars.bottom, ime.bottom) / d,
        bars.left / d,
        ime.bottom / d,
      )
      insets
    }
    ViewCompat.requestApplyInsets(webView)
  }

  // Rotation doesn't recreate the activity (`configChanges`), so the bars follow it here.
  override fun onConfigurationChanged(newConfig: Configuration) {
    super.onConfigurationChanged(newConfig)
    applyImmersive()
  }

  override fun onMultiWindowModeChanged(isInMultiWindowMode: Boolean, newConfig: Configuration) {
    super.onMultiWindowModeChanged(isInMultiWindowMode, newConfig)
    applyImmersive()
  }

  // Back from another app, which may have shown the bars.
  override fun onResume() {
    super.onResume()
    applyImmersive()
    // A grant or revoke in Settings while away shows on return (Local music's notice).
    NativeBridge.audioAccess(hasAudioAccess())
  }

  override fun onStart() {
    super.onStart()
    // Binding a controller is what creates the session service; Media3 then keeps it in the
    // foreground on its own whenever something is playing.
    if (controller == null) {
      val token = SessionToken(this, ComponentName(this, PlaybackService::class.java))
      controller = MediaController.Builder(this, token).buildAsync()
    }
  }

  // Held until the activity is destroyed, not just stopped: paused in the background, this binding
  // is all that keeps the session service (and with it the paused track's notification) alive,
  // since Media3 takes it out of the foreground on pause. Swiping the task away ends it all
  // (PlaybackService.onTaskRemoved).
  override fun onDestroy() {
    controller?.let { MediaController.releaseFuture(it) }
    controller = null
    super.onDestroy()
  }
}
