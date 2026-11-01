package com.limusic.android

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.net.Uri
import android.os.Bundle
import android.text.method.LinkMovementMethod
import android.util.TypedValue
import android.view.Gravity
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.widget.Button
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import androidx.activity.ComponentActivity
import androidx.activity.OnBackPressedCallback
import androidx.activity.enableEdgeToEdge
import androidx.core.text.HtmlCompat
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import androidx.webkit.WebViewCompat

/**
 * Which Android System WebView the app is drawn with, and whether it can draw it.
 *
 * The interface is a web page, and its whole palette is CSS `oklch()` colours (Tailwind v4, and the
 * app's own themes), which Chromium understands from version 111 on; Vite builds the scripts for the
 * same version. Older WebViews drop every colour and most of the layout with them, so below that the
 * app shows [WebViewNoticeActivity] instead of a broken page.
 */
object WebViewSupport {
  const val MIN_MAJOR = 111

  sealed class Status {
    /** Good to go, or a version that couldn't be read (not held against it). */
    data object Ok : Status()
    data class Outdated(val packageName: String, val version: String) : Status()
    /** No WebView provider installed or enabled at all. */
    data object Missing : Status()
  }

  /** `"91.0.4472.114"` → 91. Null for anything that doesn't start with a number. */
  fun majorOf(versionName: String?): Int? =
    versionName?.trim()?.substringBefore('.')?.toIntOrNull()

  fun status(packageName: String?, versionName: String?): Status {
    if (packageName == null) return Status.Missing
    val major = majorOf(versionName) ?: return Status.Ok
    return if (major < MIN_MAJOR) Status.Outdated(packageName, versionName!!.trim()) else Status.Ok
  }

  fun check(context: Context): Status {
    val pkg = try {
      WebViewCompat.getCurrentWebViewPackage(context)
    } catch (e: RuntimeException) {
      // Some devices throw while the provider is being updated. Not knowing isn't "outdated".
      android.util.Log.w("Limusic", "WebView provider not readable", e)
      return Status.Ok
    }
    return status(pkg?.packageName, pkg?.versionName)
  }
}

/**
 * Shown instead of the app when the installed WebView is too old ([WebViewSupport]) or missing. Plain
 * Android views, no WebView. Checks again on every return, so updating WebView from the Play Store
 * and coming back opens the app.
 */
class WebViewNoticeActivity : ComponentActivity() {
  private lateinit var body: TextView
  private lateinit var update: Button

  override fun onCreate(savedInstanceState: Bundle?) {
    enableEdgeToEdge()
    super.onCreate(savedInstanceState)
    setContentView(layout())
    // The app under this one can't be used, so Back leaves both, like the app's own Back does.
    onBackPressedDispatcher.addCallback(this, object : OnBackPressedCallback(true) {
      override fun handleOnBackPressed() {
        moveTaskToBack(true)
      }
    })
  }

  override fun onResume() {
    super.onResume()
    when (val s = WebViewSupport.check(this)) {
      // Updated while away. Usually Android has restarted the app for it already; if not, the app
      // underneath (singleTask) comes back on top of this.
      WebViewSupport.Status.Ok -> {
        startActivity(Intent(this, MainActivity::class.java))
        finish()
      }
      is WebViewSupport.Status.Outdated -> show(
        getString(R.string.webview_outdated_body, s.version, WebViewSupport.MIN_MAJOR),
        s.packageName,
      )
      WebViewSupport.Status.Missing -> show(getString(R.string.webview_missing_body), null)
    }
  }

  private fun show(text: String, provider: String?) {
    body.text = text
    update.visibility = if (provider != null) Button.VISIBLE else Button.GONE
    update.setOnClickListener { provider?.let(::openStore) }
  }

  private fun openStore(pkg: String) {
    try {
      startActivity(Intent(Intent.ACTION_VIEW, Uri.parse("market://details?id=$pkg")))
    } catch (e: ActivityNotFoundException) {
      open("https://play.google.com/store/apps/details?id=$pkg")
    }
  }

  private fun open(url: String) {
    try {
      startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)))
    } catch (e: ActivityNotFoundException) {
      android.util.Log.w("Limusic", "no app can open $url", e)
    }
  }

  private fun dp(v: Int) =
    TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, v.toFloat(), resources.displayMetrics).toInt()

  private fun layout(): ScrollView {
    val bg = Color.parseColor("#141217")
    val column = LinearLayout(this).apply {
      orientation = LinearLayout.VERTICAL
      gravity = Gravity.CENTER_HORIZONTAL
      setPadding(dp(28), dp(32), dp(28), dp(32))
    }
    column.addView(TextView(this).apply {
      text = getString(R.string.webview_outdated_title)
      setTextColor(Color.WHITE)
      setTextSize(TypedValue.COMPLEX_UNIT_SP, 22f)
      gravity = Gravity.CENTER
      // Read first by TalkBack: this screen is the whole app right now.
      ViewCompat.setAccessibilityHeading(this, true)
    })
    body = TextView(this).apply {
      setTextColor(Color.parseColor("#D6D1DC"))
      setTextSize(TypedValue.COMPLEX_UNIT_SP, 16f)
      setLineSpacing(0f, 1.2f)
    }
    column.addView(body, LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT).apply {
      topMargin = dp(20)
    })
    update = Button(this).apply { text = getString(R.string.webview_update) }
    column.addView(update, LinearLayout.LayoutParams(WRAP_CONTENT, WRAP_CONTENT).apply {
      topMargin = dp(24)
    })
    // The support page as a real link, focusable and announced as one.
    column.addView(TextView(this).apply {
      text = HtmlCompat.fromHtml(
        "<a href=\"$HELP_URL\">${getString(R.string.webview_help_link)}</a>",
        HtmlCompat.FROM_HTML_MODE_LEGACY,
      )
      movementMethod = LinkMovementMethod.getInstance()
      setLinkTextColor(Color.parseColor("#C9A7FF"))
      setTextSize(TypedValue.COMPLEX_UNIT_SP, 16f)
      gravity = Gravity.CENTER
      minHeight = dp(48)
    }, LinearLayout.LayoutParams(WRAP_CONTENT, WRAP_CONTENT).apply { topMargin = dp(16) })

    val scroll = ScrollView(this).apply {
      setBackgroundColor(bg)
      isFillViewport = true
    }
    scroll.addView(column, LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
    ViewCompat.setOnApplyWindowInsetsListener(scroll) { v, insets ->
      val bars = insets.getInsets(
        WindowInsetsCompat.Type.systemBars() or WindowInsetsCompat.Type.displayCutout(),
      )
      v.setPadding(bars.left, bars.top, bars.right, bars.bottom)
      WindowInsetsCompat.CONSUMED
    }
    return scroll
  }

  companion object {
    const val HELP_URL =
      "https://support.google.com/android/thread/103561027/an-update-regarding-app-crashes-and-system-webview?hl=en"

    /**
     * From MainActivity's onCreate: when the app can't run, this goes on top of it before it is
     * ever shown. MainActivity stays alive underneath rather than finishing: Tauri is still setting
     * up its WebView at that point, and an activity destroyed in the middle of that takes the
     * process down (a native abort on a destroyed mutex, seen on the emulator).
     */
    fun takeOver(from: Activity) {
      if (WebViewSupport.check(from) == WebViewSupport.Status.Ok) return
      from.startActivity(Intent(from, WebViewNoticeActivity::class.java))
    }
  }
}
