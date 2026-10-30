package com.limusic.android

import android.annotation.SuppressLint
import android.graphics.Color
import android.graphics.Bitmap
import android.net.Uri
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.webkit.CookieManager
import android.webkit.WebResourceRequest
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.Button
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.ProgressBar
import android.widget.TextView
import androidx.activity.ComponentActivity
import androidx.activity.OnBackPressedCallback
import androidx.activity.enableEdgeToEdge
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import androidx.webkit.ProfileStore
import androidx.webkit.WebViewCompat
import androidx.webkit.WebViewFeature
import java.lang.ref.WeakReference

/**
 * Google's own sign-in page, for a YouTube Music session (the Android side of `session::open_login`).
 *
 * What makes this honest rather than clever:
 * * The page is accounts.google.com itself, in a WebView with its stock user agent: nothing is
 *   disguised as another browser or app, and the address bar line under the title shows which
 *   site the page is on at every step. The user types their password into Google's page; Limusic
 *   never sees it.
 * * The only thing taken from the WebView is what the desktop's sign-in window takes: the
 *   music.youtube.com cookies the sign-in ends with, read once the page lands there. They go to
 *   Rust's `AppState::sign_in` (`NativeBridge.signInCookie`), which checks them against YouTube
 *   before keeping anything, and this screen closes only once that check has passed.
 * * The WebView runs in a profile of its own ([PROFILE]), so its jar is separate from the app's
 *   main WebView, and "add account" can empty it without touching anything else.
 *
 * Whether Google lets an account sign in here is up to Google. If it refuses, the cookie paste
 * (CookieSignIn.svelte) is still there.
 */
class SignInActivity : ComponentActivity() {
  companion object {
    const val EXTRA_ADD_ACCOUNT = "add_account"
    private const val PROFILE = "google-sign-in"
    private const val LOGIN_URL =
      "https://accounts.google.com/ServiceLogin?service=youtube&continue=https://music.youtube.com/"
    private const val ADD_ACCOUNT_URL =
      "https://accounts.google.com/AddSession?service=youtube&continue=https://music.youtube.com/"
    private const val DONE_HOST = "music.youtube.com"

    private var current = WeakReference<SignInActivity>(null)

    /** Rust's verdict on the cookies (`android::sign_in_finished`). Main thread. */
    fun finished(ok: Boolean, message: String?) {
      val a = current.get()?.takeUnless { it.isFinishing || it.isDestroyed } ?: return
      if (ok) a.finish() else a.showError(message)
    }

    /** `SAPISID` or `__Secure-3PAPISID`: what the SAPISIDHASH header is made from. */
    internal fun hasSession(cookie: String?) = cookie != null && cookie.split(';').any {
      val name = it.substringBefore('=').trim()
      name == "SAPISID" || name == "__Secure-3PAPISID"
    }
  }

  private val main = Handler(Looper.getMainLooper())
  private lateinit var web: WebView
  private lateinit var cookies: CookieManager
  private lateinit var site: TextView
  private lateinit var loading: ProgressBar
  private lateinit var status: LinearLayout
  private lateinit var statusText: TextView
  private lateinit var retry: Button
  /** A capture is underway or the cookies are with Rust: don't start another. */
  private var capturing = false

  @SuppressLint("SetJavaScriptEnabled")
  override fun onCreate(savedInstanceState: Bundle?) {
    enableEdgeToEdge()
    super.onCreate(savedInstanceState)
    current = WeakReference(this)

    web = WebView(this)
    // Its own jar. Without multi-profile support the jar would be the main WebView's, and "add
    // account" could not empty it without emptying that too, so the paste has to do instead.
    if (!WebViewFeature.isFeatureSupported(WebViewFeature.MULTI_PROFILE)) {
      setContentView(TextView(this))
      showError(getString(R.string.sign_in_unsupported))
      return
    }
    WebViewCompat.setProfile(web, PROFILE)
    cookies = ProfileStore.getInstance().getOrCreateProfile(PROFILE).cookieManager
    cookies.setAcceptCookie(true)
    cookies.setAcceptThirdPartyCookies(web, true)
    web.settings.javaScriptEnabled = true
    web.settings.domStorageEnabled = true
    web.webViewClient = Client()

    setContentView(layout())
    onBackPressedDispatcher.addCallback(this, object : OnBackPressedCallback(true) {
      override fun handleOnBackPressed() {
        if (web.visibility == View.VISIBLE && web.canGoBack()) web.goBack() else finish()
      }
    })

    val addAccount = intent.getBooleanExtra(EXTRA_ADD_ACCOUNT, false)
    if (addAccount) {
      // A fresh jar, so Google asks for the new account instead of continuing into the last one.
      // The app's saved accounts live in its database, not in this profile.
      cookies.removeAllCookies { web.loadUrl(ADD_ACCOUNT_URL) }
    } else {
      web.loadUrl(LOGIN_URL)
    }
  }

  override fun onDestroy() {
    main.removeCallbacksAndMessages(null)
    if (::web.isInitialized) web.destroy()
    if (current.get() === this) current = WeakReference(null)
    super.onDestroy()
  }

  private fun dp(v: Int) =
    TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, v.toFloat(), resources.displayMetrics).toInt()

  private fun layout(): View {
    val bg = Color.parseColor("#141217")
    val root = LinearLayout(this).apply {
      orientation = LinearLayout.VERTICAL
      setBackgroundColor(bg)
    }
    val bar = LinearLayout(this).apply {
      orientation = LinearLayout.HORIZONTAL
      gravity = Gravity.CENTER_VERTICAL
      setPadding(dp(16), dp(8), dp(8), dp(8))
    }
    val titles = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
    titles.addView(TextView(this).apply {
      text = getString(R.string.sign_in_title)
      setTextColor(Color.WHITE)
      setTextSize(TypedValue.COMPLEX_UNIT_SP, 17f)
    })
    site = TextView(this).apply {
      setTextColor(Color.parseColor("#A8A3AE"))
      setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
      isSingleLine = true
    }
    titles.addView(site)
    bar.addView(titles, LinearLayout.LayoutParams(0, WRAP_CONTENT, 1f))
    bar.addView(Button(this, null, android.R.attr.borderlessButtonStyle).apply {
      text = getString(R.string.sign_in_cancel)
      setTextColor(Color.WHITE)
      setOnClickListener { finish() }
    })
    root.addView(bar, LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT))

    loading = ProgressBar(this, null, android.R.attr.progressBarStyleHorizontal).apply {
      isIndeterminate = true
    }
    root.addView(loading, LinearLayout.LayoutParams(MATCH_PARENT, dp(3)))

    val body = FrameLayout(this)
    body.addView(web, FrameLayout.LayoutParams(MATCH_PARENT, MATCH_PARENT))
    status = LinearLayout(this).apply {
      orientation = LinearLayout.VERTICAL
      gravity = Gravity.CENTER
      setPadding(dp(32), dp(32), dp(32), dp(32))
      setBackgroundColor(bg)
      visibility = View.GONE
    }
    statusText = TextView(this).apply {
      setTextColor(Color.WHITE)
      setTextSize(TypedValue.COMPLEX_UNIT_SP, 16f)
      gravity = Gravity.CENTER
    }
    status.addView(statusText)
    retry = Button(this).apply {
      text = getString(R.string.sign_in_retry)
      visibility = View.GONE
      setOnClickListener { restart() }
    }
    status.addView(retry, LinearLayout.LayoutParams(WRAP_CONTENT, WRAP_CONTENT).apply {
      topMargin = dp(16)
    })
    body.addView(status, FrameLayout.LayoutParams(MATCH_PARENT, MATCH_PARENT))
    root.addView(body, LinearLayout.LayoutParams(MATCH_PARENT, 0, 1f))

    // Edge to edge: keep the bar below the status bar and the page above the navigation bar and
    // the keyboard.
    ViewCompat.setOnApplyWindowInsetsListener(root) { v, insets ->
      val bars = insets.getInsets(
        WindowInsetsCompat.Type.systemBars() or WindowInsetsCompat.Type.displayCutout() or
          WindowInsetsCompat.Type.ime(),
      )
      v.setPadding(bars.left, bars.top, bars.right, bars.bottom)
      WindowInsetsCompat.CONSUMED
    }
    return root
  }

  private fun showStatus(text: String, canRetry: Boolean) {
    if (!::statusText.isInitialized) return
    statusText.text = text
    retry.visibility = if (canRetry) View.VISIBLE else View.GONE
    status.visibility = View.VISIBLE
    web.visibility = View.INVISIBLE
  }

  fun showError(message: String?) {
    capturing = false
    if (!::statusText.isInitialized) {
      // No layout (an unsupported WebView): say so on the placeholder and let Back close it.
      (window.decorView.findViewById<ViewGroup>(android.R.id.content).getChildAt(0) as? TextView)?.apply {
        text = message ?: getString(R.string.sign_in_failed)
        setTextColor(Color.WHITE)
        setBackgroundColor(Color.parseColor("#141217"))
        gravity = Gravity.CENTER
        setPadding(dp(32), dp(32), dp(32), dp(32))
      }
      return
    }
    loading.visibility = View.INVISIBLE
    showStatus(
      getString(R.string.sign_in_failed) + (message?.let { "\n\n$it" } ?: ""),
      canRetry = true,
    )
  }

  /** Back to Google's page with the same jar: a session that half-worked gets another go. */
  private fun restart() {
    capturing = false
    status.visibility = View.GONE
    web.visibility = View.VISIBLE
    web.loadUrl(LOGIN_URL)
  }

  /**
   * The sign-in redirect has landed on music.youtube.com. Its cookies can appear a beat after the
   * page reports finished, so look a few times before deciding the session isn't there yet (a
   * signed-out visit lands here too, from "continue without signing in" links).
   */
  private fun capture(attempt: Int = 0) {
    if (!capturing || isFinishing) return
    val cookie = cookies.getCookie("https://$DONE_HOST")
    if (hasSession(cookie)) {
      cookies.flush()
      showStatus(getString(R.string.sign_in_checking), canRetry = false)
      NativeBridge.signInCookie(cookie!!)
    } else if (attempt < 6) {
      main.postDelayed({ capture(attempt + 1) }, 500)
    } else {
      // Landed signed out: put Google's page back rather than sitting on YouTube Music.
      capturing = false
      web.loadUrl(LOGIN_URL)
    }
  }

  private inner class Client : WebViewClient() {
    override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean {
      // https pages only. Anything else (an intent: link, a store link) stays out of the sign-in.
      return request.url.scheme != "https"
    }

    override fun onPageStarted(view: WebView, url: String, favicon: Bitmap?) {
      site.text = Uri.parse(url).host ?: ""
      loading.visibility = View.VISIBLE
    }

    override fun onPageFinished(view: WebView, url: String) {
      loading.visibility = View.INVISIBLE
      if (Uri.parse(url).host == DONE_HOST && !capturing) {
        capturing = true
        capture()
      }
    }
  }
}
