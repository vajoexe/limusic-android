package com.limusic.android

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/** Which URL IpcOrigin reports for the first page: only the app's own, only over about:blank. */
class IpcOriginTest {
  @Test
  fun theAppPageReplacesTheStartingBlank() {
    assertEquals("http://tauri.localhost/", IpcOrigin.startUrl("about:blank", "http://tauri.localhost/"))
    assertEquals("https://tauri.localhost/", IpcOrigin.startUrl("about:blank", "https://tauri.localhost/"))
    assertEquals("http://tauri.localhost/?x=1", IpcOrigin.startUrl(null, "http://tauri.localhost/?x=1"))
  }

  @Test
  fun aPageAndroidAlreadyReportedIsLeftAlone() {
    // onPageStarted got there first: it knows better.
    assertNull(IpcOrigin.startUrl("http://tauri.localhost/", "http://tauri.localhost/"))
    assertNull(IpcOrigin.startUrl("https://example.com/", "http://tauri.localhost/"))
  }

  @Test
  fun nothingButTheAppPageIsEverReported() {
    assertNull(IpcOrigin.startUrl("about:blank", null))
    assertNull(IpcOrigin.startUrl("about:blank", "about:blank"))
    assertNull(IpcOrigin.startUrl("about:blank", "https://example.com/"))
    assertNull(IpcOrigin.startUrl("about:blank", "http://tauri.localhost.example.com/"))
    assertNull(IpcOrigin.startUrl("about:blank", "http://evil.tauri.localhost/"))
    assertNull(IpcOrigin.startUrl("about:blank", "http://tauri.localhost:8080/"))
    assertNull(IpcOrigin.startUrl("about:blank", "http://user@tauri.localhost/"))
    assertNull(IpcOrigin.startUrl("about:blank", "file:///android_asset/index.html"))
    assertNull(IpcOrigin.startUrl("about:blank", "javascript:alert(1)"))
    assertNull(IpcOrigin.startUrl("about:blank", "not a url"))
  }
}
