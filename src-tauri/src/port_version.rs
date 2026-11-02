//! The Android port's version: the upstream desktop version it is built on (the crate version,
//! `1.4.0-rc.3`) plus the port's own revision on top of it (`android-port.properties`, handed in
//! by build.rs as `LIMUSIC_ANDROID_REVISION`).
//!
//! It is written `1.4.0-rc.3-universal-android.2` for the APK, which carries both architectures,
//! and `1.4.0-rc.3-arm64-v8a-android.2` (or `-x86_64-`) for the copy running. The architecture is
//! a label, not part of the version: two names that differ only there are the same release.
//!
//! Compiled everywhere so the comparison is tested with the rest of the suite; only Android uses it.
#![cfg_attr(not(target_os = "android"), allow(dead_code))]

use std::cmp::Ordering;

const UPSTREAM: &str = env!("CARGO_PKG_VERSION");
const REVISION: &str = env!("LIMUSIC_ANDROID_REVISION");

/// Labels a release name may carry between the upstream version and `-android.N`. Anything else
/// there (a `beta.1`, a typo) makes the name unreadable rather than silently equal to something.
const LABELS: &[&str] = &["universal", "arm64", "v8a", "x86_64"];

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct PortVersion {
    major: u32,
    minor: u32,
    patch: u32,
    /// The upstream release candidate, `None` for a final release.
    rc: Option<u32>,
    revision: u32,
}

impl Ord for PortVersion {
    fn cmp(&self, other: &Self) -> Ordering {
        (self.major, self.minor, self.patch)
            .cmp(&(other.major, other.minor, other.patch))
            // A final release comes after every one of its release candidates.
            .then_with(|| match (self.rc, other.rc) {
                (None, None) => Ordering::Equal,
                (None, Some(_)) => Ordering::Greater,
                (Some(_), None) => Ordering::Less,
                (Some(a), Some(b)) => a.cmp(&b),
            })
            .then_with(|| self.revision.cmp(&other.revision))
    }
}

impl PartialOrd for PortVersion {
    fn partial_cmp(&self, other: &Self) -> Option<Ordering> {
        Some(self.cmp(other))
    }
}

/// `v1.4.0-rc.3-universal-android.2`, `1.4.0-rc.3-x86_64-android.2`, `v1.4.0-android.1`: a release
/// tag or a version name. `None` for anything that isn't one, which the update check takes as
/// "no update", never as "older" or "newer".
pub fn parse(name: &str) -> Option<PortVersion> {
    let name = name.trim();
    let name = name.strip_prefix('v').unwrap_or(name);
    let (head, revision) = name.rsplit_once("-android.")?;
    let revision = revision.parse().ok()?;
    let mut parts = head.split('-');
    let mut numbers = parts.next()?.split('.').map(|n| n.parse::<u32>().ok());
    let (Some(Some(major)), Some(Some(minor)), Some(Some(patch)), None) =
        (numbers.next(), numbers.next(), numbers.next(), numbers.next())
    else {
        return None;
    };
    let mut rc = None;
    for part in parts {
        if let Some(n) = part.strip_prefix("rc.") {
            if rc.is_some() {
                return None;
            }
            rc = Some(n.parse().ok()?);
        } else if !LABELS.contains(&part) {
            return None;
        }
    }
    Some(PortVersion { major, minor, patch, rc, revision })
}

/// This build's version, `None` only if `android-port.properties` held something unreadable.
pub fn installed() -> Option<PortVersion> {
    parse(&format!("{UPSTREAM}-android.{REVISION}"))
}

/// The release's name: `1.4.0-rc.3-universal-android.2`.
pub fn release_name() -> String {
    format!("{UPSTREAM}-universal-android.{REVISION}")
}

/// The copy running, as the About page shows it: `1.4.0-rc.3-arm64-v8a-android.2`.
pub fn running_name() -> String {
    format!("{UPSTREAM}-{}-android.{REVISION}", running_abi())
}

/// The Android ABI of the code running. The library Android loaded is the one for this
/// architecture, so on an x86_64 device that translates ARM code this would say arm64-v8a, and
/// that would be true.
pub fn running_abi() -> &'static str {
    match std::env::consts::ARCH {
        "aarch64" => "arm64-v8a",
        "x86_64" => "x86_64",
        "arm" => "armeabi-v7a",
        "x86" => "x86",
        other => other,
    }
}

/// Whether `latest` (a release tag) is a newer release than this build. Unreadable on either
/// side is "no": a broken tag must not nag every user, and a broken build has nothing to say.
pub fn is_update(latest: &str) -> bool {
    match (parse(latest), installed()) {
        (Some(latest), Some(installed)) => latest > installed,
        _ => false,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn v(s: &str) -> PortVersion {
        parse(s).unwrap_or_else(|| panic!("{s} should parse"))
    }

    #[test]
    fn reads_every_way_a_release_is_written() {
        let want = PortVersion { major: 1, minor: 4, patch: 0, rc: Some(3), revision: 2 };
        for name in [
            "1.4.0-rc.3-universal-android.2",
            "v1.4.0-rc.3-universal-android.2",
            "1.4.0-rc.3-arm64-v8a-android.2",
            "1.4.0-rc.3-x86_64-android.2",
            "v1.4.0-rc.3-android.2",
            " v1.4.0-rc.3-universal-android.2\n",
        ] {
            assert_eq!(parse(name), Some(want), "{name}");
        }
        assert_eq!(v("v1.4.0-android.1").rc, None);
    }

    #[test]
    fn refuses_what_is_not_a_port_release() {
        for name in [
            "",
            "1.4.0-rc.3",
            "1.4.0",
            "v1.4.0-rc.3-android.",
            "v1.4.0-rc.3-android.x",
            "1.4-rc.3-android.2",
            "1.4.0.1-android.2",
            "1.4.0-beta.1-android.2",
            "1.4.0-rc.3-rc.4-android.2",
            "1.4.0-rc.x-android.2",
            "latest",
        ] {
            assert_eq!(parse(name), None, "{name:?}");
        }
    }

    #[test]
    fn architecture_is_not_part_of_the_version() {
        assert_eq!(v("1.4.0-rc.3-arm64-v8a-android.2"), v("1.4.0-rc.3-x86_64-android.2"));
        assert_eq!(v("1.4.0-rc.3-x86_64-android.2"), v("v1.4.0-rc.3-universal-android.2"));
    }

    #[test]
    fn orders_upstream_first_then_the_port_revision() {
        // The port revision, on the same upstream version.
        assert!(v("1.4.0-rc.3-android.2") > v("1.4.0-rc.3-android.1"));
        assert!(v("1.4.0-rc.3-android.10") > v("1.4.0-rc.3-android.9"));
        // A newer release candidate wins whatever the revisions: they restart at 1.
        assert!(v("1.4.0-rc.4-android.1") > v("1.4.0-rc.3-android.7"));
        // The final release after all of its release candidates.
        assert!(v("1.4.0-android.1") > v("1.4.0-rc.9-android.9"));
        // Then the upstream numbers, compared as numbers.
        assert!(v("1.4.1-rc.1-android.1") > v("1.4.0-android.5"));
        assert!(v("1.10.0-android.1") > v("1.9.0-android.1"));
        assert!(v("2.0.0-rc.1-android.1") > v("1.99.99-android.99"));
        assert_eq!(
            v("1.4.0-rc.3-android.2").cmp(&v("v1.4.0-rc.3-universal-android.2")),
            Ordering::Equal
        );
    }

    #[test]
    fn this_build_reads_back_as_itself() {
        let me = installed().expect("android-port.properties holds a readable revision");
        assert_eq!(parse(&release_name()), Some(me));
        assert_eq!(parse(&running_name()), Some(me));
        assert!(!is_update(&release_name()));
        assert!(!is_update(&format!("v{}", running_name())));
    }

    #[test]
    fn an_update_is_strictly_newer() {
        let me = installed().unwrap();
        let next = format!("v{UPSTREAM}-universal-android.{}", me.revision + 1);
        assert!(is_update(&next));
        if me.revision > 1 {
            assert!(!is_update(&format!("v{UPSTREAM}-universal-android.{}", me.revision - 1)));
        }
        assert!(!is_update("v0.1.0-android.99"));
        assert!(!is_update("not a version"));
    }
}
