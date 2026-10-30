//! BotGuard on a platform with no V8 (Android). Same surface as `botguard.rs`, and every bootstrap
//! answers [`Error::Fatal`], which makes [`super::PoTokenGenerator`] latch `runtime_bad` and send
//! every resolve to the non-PoToken clients: the same degradation a desktop gets when V8 cannot be
//! stood up at all (context/04 §BadWebViewException).
//!
//! `rustypipe-botguard` runs on deno_core, and rusty_v8 publishes no Android build of any release
//! the crate can use. A real browser engine is no substitute: googlevideo rejects every token one
//! mints (`botguard.rs`, KNOWN-ISSUES KI-1), so the Android WebView cannot stand in. The cost is
//! that playback leans on the client fallback chain alone; an Android build of V8 would restore it.

#[derive(Debug, thiserror::Error)]
pub enum Error {
    #[error("botguard runtime: {0}")]
    Fatal(String),
    #[allow(dead_code)]
    #[error("botguard: {0}")]
    Transient(String),
}

pub struct Minter {
    _private: (),
}

pub struct Bootstrap {
    pub minter: Minter,
    pub session_token: String,
    pub lifetime_secs: u64,
}

impl Minter {
    pub async fn spawn(_user_agent: String, _session_ident: String) -> Result<Bootstrap, Error> {
        Err(Error::Fatal("no JavaScript runtime for BotGuard on this platform".into()))
    }

    pub async fn mint(&self, _ident: &str) -> Result<String, Error> {
        Err(Error::Fatal("no JavaScript runtime for BotGuard on this platform".into()))
    }
}
