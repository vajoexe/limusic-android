package com.limusic.android

import android.os.Handler
import android.os.Looper
import android.os.Message
import android.webkit.WebView
import java.net.URI

/**
 * Closes a startup race in wry 0.55's Android IPC that made Tauri refuse every command the page
 * sent before Android had reported the page as started.
 *
 * Every `invoke` reaches Rust through wry's `Ipc.postMessage`, which sends along
 * `RustWebViewClient.currentUrl` as the page's URL. Tauri allows the app's own commands only from
 * the app's local origin, and that field starts out as `about:blank` and is only updated in
 * `onPageStarted`, on the main thread. The page's scripts run in the renderer meanwhile, so when
 * the main thread is slow to get to `onPageStarted`, the first calls arrive "from about:blank",
 * count as a remote page and are refused: `get_home not allowed. Plugin not found`, in release
 * builds `Command get_home not allowed by ACL`. The home feed then fails, and so does every
 * `listen` the page set up at that moment, insets included.
 *
 * The fix sets `currentUrl` to the page the WebView is loading, as soon as the client exists:
 * one main-thread task after the WebView is created, which is before the first navigation is
 * even sent to the renderer (the WebView runs its navigation on the main thread too), so before
 * any page script can call `postMessage`. Only the app's own `tauri.localhost` page is ever put
 * there, and only over the starting `about:blank`; every later navigation still goes through
 * `onPageStarted` as before, so the ACL keeps deciding on what is really loaded.
 *
 * wry fixed this upstream (tauri-apps/wry#1891, taking the URL from the sending frame's origin);
 * this goes once the port is on a Tauri that ships that wry.
 */
object IpcOrigin {
  private const val BLANK = "about:blank"
  private const val APP_HOST = "tauri.localhost"

  /** The URL to report for the page, or null to leave `current` as it is. */
  fun startUrl(current: String?, loading: String?): String? {
    if (current != null && current != BLANK) return null
    val uri = loading?.let { runCatching { URI(it) }.getOrNull() } ?: return null
    val scheme = uri.scheme?.lowercase()
    if (scheme != "http" && scheme != "https") return null
    if (!APP_HOST.equals(uri.host, ignoreCase = true)) return null
    // An explicit port or user info is not how Tauri serves the app, so not the app's page.
    if (uri.port != -1 || uri.rawUserInfo != null) return null
    return loading
  }

  /** How often to look again for the page's URL before giving up (1 ms apart). */
  private const val ATTEMPTS = 200

  /**
   * From `onWebViewCreate`. wry sets the client and posts the WebView's `loadUrl` after this
   * returns, so the URL is set from a message queued behind that `loadUrl`: one hop to get behind
   * it, then the setter. The setter is asynchronous, like the WebView's own main-thread tasks: an
   * ordinary message waits behind the layout barrier that setContentView puts up, and the
   * navigation would not. If it still runs before `loadUrl` (it can, past such a barrier), it looks
   * again shortly.
   */
  fun install(webView: WebView) {
    val handler = Handler(Looper.getMainLooper())
    fun attempt(left: Int) {
      val client = webView.webViewClient as? RustWebViewClient ?: return
      if (client.currentUrl != BLANK) return // onPageStarted got there first
      val loading = webView.url
      if (loading == null) {
        if (left > 0) {
          handler.sendMessageDelayed(Message.obtain(handler) { attempt(left - 1) }.apply { isAsynchronous = true }, 1)
        }
        return
      }
      val url = startUrl(client.currentUrl, loading) ?: return
      client.currentUrl = url
      if (BuildConfig.DEBUG) android.util.Log.d("Limusic", "IPC origin set to $url before the page started")
    }
    webView.post {
      handler.sendMessage(Message.obtain(handler) { attempt(ATTEMPTS) }.apply { isAsynchronous = true })
    }
  }
}
