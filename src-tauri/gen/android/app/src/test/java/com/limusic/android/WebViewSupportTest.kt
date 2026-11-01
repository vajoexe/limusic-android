package com.limusic.android

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/** The startup check's verdicts, from the provider's package and version name alone. */
class WebViewSupportTest {
  @Test
  fun readsTheMajorVersion() {
    assertEquals(91, WebViewSupport.majorOf("91.0.4472.114"))
    assertEquals(159, WebViewSupport.majorOf(" 159.0.8130.0 "))
    assertNull(WebViewSupport.majorOf(""))
    assertNull(WebViewSupport.majorOf("dev-build"))
    assertNull(WebViewSupport.majorOf(null))
  }

  @Test
  fun belowTheMinimumIsOutdated() {
    assertEquals(
      WebViewSupport.Status.Outdated("com.google.android.webview", "91.0.4472.114"),
      WebViewSupport.status("com.google.android.webview", "91.0.4472.114"),
    )
    assertEquals(
      WebViewSupport.Status.Outdated("com.google.android.webview", "110.0.5481.153"),
      WebViewSupport.status("com.google.android.webview", "110.0.5481.153"),
    )
  }

  @Test
  fun theMinimumAndNewerRun() {
    assertEquals(WebViewSupport.Status.Ok, WebViewSupport.status("com.google.android.webview", "111.0.5563.116"))
    assertEquals(WebViewSupport.Status.Ok, WebViewSupport.status("com.google.android.webview.dev", "159.0.8130.0"))
  }

  @Test
  fun anUnreadableVersionIsNotHeldAgainstIt() {
    assertEquals(WebViewSupport.Status.Ok, WebViewSupport.status("com.android.webview", "custom"))
    assertEquals(WebViewSupport.Status.Ok, WebViewSupport.status("com.android.webview", null))
  }

  @Test
  fun noProviderIsMissing() {
    assertEquals(WebViewSupport.Status.Missing, WebViewSupport.status(null, null))
  }
}
