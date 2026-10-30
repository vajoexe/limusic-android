package com.limusic.android

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** What SignInActivity accepts as "the sign-in landed": a SAPISID-family cookie, by name only. */
class SignInSessionTest {
  @Test
  fun aSignedInJarHasTheSapisidCookie() {
    assertTrue(SignInActivity.hasSession("VISITOR_INFO1_LIVE=a; SAPISID=b; SID=c"))
    assertTrue(SignInActivity.hasSession("__Secure-3PAPISID=b"))
    assertTrue(SignInActivity.hasSession(" PREF=x ;  SAPISID=b "))
  }

  @Test
  fun aSignedOutVisitIsNotASession() {
    assertFalse(SignInActivity.hasSession(null))
    assertFalse(SignInActivity.hasSession(""))
    assertFalse(SignInActivity.hasSession("VISITOR_INFO1_LIVE=a; YSC=b; PREF=c"))
  }

  @Test
  fun onlyTheCookieNameCounts() {
    // A value that merely mentions the name, or a longer name, is not the cookie.
    assertFalse(SignInActivity.hasSession("PREF=SAPISID=1"))
    assertFalse(SignInActivity.hasSession("XSAPISID=1; SAPISIDX=2"))
  }
}
