//! Reading the GitHub releases API (the changelog in Settings > About, the Android update check),
//! with its failures sorted into what the UI can say and whether waiting will help.
//!
//! Unauthenticated, the API allows 60 requests an hour per IP address, shared by everything behind
//! that address. Right after a release, people checking at once (or a shared VPN exit) run out of
//! them, and GitHub answers 403 or 429 until the window resets, saying when in `Retry-After` or
//! `x-ratelimit-reset`. That is temporary; a 404 or a body that isn't the expected JSON is not.

use std::time::{Duration, SystemTime, UNIX_EPOCH};

/// The API's base URL. A debug build can point it at a local stand-in (set
/// `LIMUSIC_GITHUB_API=http://10.0.2.2:8787` when building) to test rate limits and outages
/// without waiting for GitHub to produce them. Release builds always use GitHub.
pub fn base() -> &'static str {
    #[cfg(debug_assertions)]
    if let Some(url) = option_env!("LIMUSIC_GITHUB_API") {
        return url;
    }
    "https://api.github.com"
}

/// Why a request failed, as the frontend gets it: `{"kind": "rate_limited", "status": 403,
/// "retry_after_secs": 120}`. Nothing from the response body is passed on.
#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize)]
#[serde(tag = "kind", rename_all = "snake_case")]
pub enum FetchError {
    /// 403 or 429 from the rate limiter. `retry_after_secs` is how long GitHub said to wait, when it
    /// said.
    RateLimited { status: u16, retry_after_secs: Option<u64> },
    /// 5xx: GitHub's side, usually brief.
    Server { status: u16 },
    /// Any other 4xx (404, a 403 that is not the rate limiter). Retrying won't change it.
    Http { status: u16 },
    /// No answer at all: offline, DNS, TLS, a timeout.
    Network,
    /// An answer that isn't the JSON expected.
    Malformed,
}

impl FetchError {
    /// Whether trying again later can help. The UI retries these on its own; the others only when
    /// asked to.
    #[cfg_attr(not(test), allow(dead_code))]
    pub fn transient(&self) -> bool {
        matches!(self, Self::RateLimited { .. } | Self::Server { .. } | Self::Network)
    }
}

impl std::fmt::Display for FetchError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::RateLimited { status, retry_after_secs: Some(s) } => {
                write!(f, "rate limited (HTTP {status}), retry in {s} s")
            }
            Self::RateLimited { status, retry_after_secs: None } => {
                write!(f, "rate limited (HTTP {status})")
            }
            Self::Server { status } | Self::Http { status } => write!(f, "HTTP {status}"),
            Self::Network => f.write_str("network error"),
            Self::Malformed => f.write_str("unexpected response"),
        }
    }
}

/// Never wait longer than GitHub's own window: a reset time further out than that is a clock
/// problem on one side or the other.
const MAX_WAIT_SECS: u64 = 3600;

/// How long GitHub asked to wait: `Retry-After` (seconds; GitHub doesn't send the date form), else
/// the primary limit's reset time, `x-ratelimit-reset` (Unix seconds) minus now.
pub fn retry_after(headers: &reqwest::header::HeaderMap, now: SystemTime) -> Option<u64> {
    let header = |name: &str| headers.get(name).and_then(|v| v.to_str().ok()).map(str::trim);
    if let Some(secs) = header("retry-after").and_then(|v| v.parse::<u64>().ok()) {
        return Some(secs.min(MAX_WAIT_SECS));
    }
    let reset = header("x-ratelimit-reset")?.parse::<u64>().ok()?;
    let now = now.duration_since(UNIX_EPOCH).ok()?.as_secs();
    // A reset that has just passed still needs a moment to take effect.
    Some(reset.saturating_sub(now).clamp(1, MAX_WAIT_SECS))
}

/// Sorts a failed status. `body` is only looked at for a 403, where GitHub's secondary rate limit
/// says so in the text and sometimes sends no headers.
pub fn classify(
    status: u16,
    headers: &reqwest::header::HeaderMap,
    body: &str,
    now: SystemTime,
) -> FetchError {
    let exhausted = headers
        .get("x-ratelimit-remaining")
        .and_then(|v| v.to_str().ok())
        .is_some_and(|v| v.trim() == "0");
    match status {
        429 => FetchError::RateLimited { status, retry_after_secs: retry_after(headers, now) },
        403 if exhausted
            || headers.contains_key("retry-after")
            || body.to_ascii_lowercase().contains("rate limit") =>
        {
            FetchError::RateLimited { status, retry_after_secs: retry_after(headers, now) }
        }
        500..=599 => FetchError::Server { status },
        _ => FetchError::Http { status },
    }
}

/// GET `path` (`/repos/owner/name/releases`) as JSON.
pub async fn get_json<T: serde::de::DeserializeOwned>(
    path: &str,
    timeout: Duration,
) -> Result<T, FetchError> {
    let resp = crate::http::client()
        .get(format!("{}{path}", base()))
        .header("User-Agent", concat!("Limusic/", env!("CARGO_PKG_VERSION")))
        .header("Accept", "application/vnd.github+json")
        .timeout(timeout)
        .send()
        .await
        .map_err(|e| {
            tracing::debug!(error = %e, "github: request failed");
            FetchError::Network
        })?;
    let status = resp.status();
    let headers = resp.headers().clone();
    let body = resp.text().await.map_err(|_| FetchError::Network)?;
    if !status.is_success() {
        let e = classify(status.as_u16(), &headers, &body, SystemTime::now());
        tracing::info!(path, error = %e, "github: request refused");
        return Err(e);
    }
    serde_json::from_str(&body).map_err(|e| {
        tracing::info!(path, error = %e, "github: unexpected response");
        FetchError::Malformed
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use reqwest::header::{HeaderMap, HeaderValue};

    fn headers(pairs: &[(&'static str, &str)]) -> HeaderMap {
        let mut h = HeaderMap::new();
        for (k, v) in pairs {
            h.insert(*k, HeaderValue::from_str(v).unwrap());
        }
        h
    }

    const NOW: u64 = 1_800_000_000;
    fn now() -> SystemTime {
        UNIX_EPOCH + Duration::from_secs(NOW)
    }

    #[test]
    fn primary_rate_limit_waits_for_the_reset() {
        let h = headers(&[
            ("x-ratelimit-remaining", "0"),
            ("x-ratelimit-reset", &(NOW + 754).to_string()),
        ]);
        let e = classify(403, &h, "{\"message\":\"API rate limit exceeded for 1.2.3.4.\"}", now());
        assert_eq!(e, FetchError::RateLimited { status: 403, retry_after_secs: Some(754) });
        assert!(e.transient());
    }

    #[test]
    fn retry_after_wins_over_the_reset_time() {
        let h = headers(&[("retry-after", "60"), ("x-ratelimit-reset", &(NOW + 900).to_string())]);
        assert_eq!(
            classify(429, &h, "", now()),
            FetchError::RateLimited { status: 429, retry_after_secs: Some(60) }
        );
    }

    #[test]
    fn secondary_rate_limit_is_known_by_its_message() {
        let e = classify(403, &HeaderMap::new(), "You have exceeded a secondary rate limit", now());
        assert_eq!(e, FetchError::RateLimited { status: 403, retry_after_secs: None });
    }

    #[test]
    fn a_plain_403_or_404_is_not_retried() {
        let h = headers(&[("x-ratelimit-remaining", "42")]);
        let forbidden = classify(403, &h, "{\"message\":\"Repository access blocked\"}", now());
        assert_eq!(forbidden, FetchError::Http { status: 403 });
        assert!(!forbidden.transient());
        assert!(!classify(404, &HeaderMap::new(), "", now()).transient());
    }

    #[test]
    fn server_errors_are_transient() {
        for s in [500, 502, 503, 504] {
            let e = classify(s, &HeaderMap::new(), "", now());
            assert_eq!(e, FetchError::Server { status: s });
            assert!(e.transient());
        }
        assert!(FetchError::Network.transient());
        assert!(!FetchError::Malformed.transient());
    }

    #[test]
    fn waits_are_bounded() {
        // A reset in the past still waits a second; one a day out is held to an hour; nonsense
        // headers give no wait at all rather than a made-up one.
        let past = headers(&[("x-ratelimit-reset", &(NOW - 30).to_string())]);
        assert_eq!(retry_after(&past, now()), Some(1));
        let far = headers(&[("x-ratelimit-reset", &(NOW + 86_400).to_string())]);
        assert_eq!(retry_after(&far, now()), Some(MAX_WAIT_SECS));
        assert_eq!(retry_after(&headers(&[("retry-after", "99999")]), now()), Some(MAX_WAIT_SECS));
        let junk = headers(&[("retry-after", "Wed, 21 Oct 2015 07:28:00 GMT")]);
        assert_eq!(retry_after(&junk, now()), None);
    }

    #[test]
    fn serializes_for_the_frontend() {
        let e = FetchError::RateLimited { status: 429, retry_after_secs: Some(60) };
        assert_eq!(
            serde_json::to_string(&e).unwrap(),
            r#"{"kind":"rate_limited","status":429,"retry_after_secs":60}"#
        );
        assert_eq!(serde_json::to_string(&FetchError::Network).unwrap(), r#"{"kind":"network"}"#);
    }
}
