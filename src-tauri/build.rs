fn main() {
    // Last.fm API credentials live in a gitignored `lastfm.keys` next to this file (the repo is
    // public — they must never be tracked). Format: `LIMUSIC_LASTFM_API_KEY=…` and
    // `LIMUSIC_LASTFM_API_SECRET=…`, one per line. Exported as compile-time env for `option_env!`
    // in lastfm.rs; missing file just means the scrobbler reports "not configured".
    println!("cargo:rerun-if-changed=lastfm.keys");
    if let Ok(keys) = std::fs::read_to_string("lastfm.keys") {
        for line in keys.lines() {
            if let Some((k, v)) = line.split_once('=') {
                let (k, v) = (k.trim(), v.trim());
                if k == "LIMUSIC_LASTFM_API_KEY" || k == "LIMUSIC_LASTFM_API_SECRET" {
                    println!("cargo:rustc-env={k}={v}");
                }
            }
        }
    }
    // The Android port's revision (port_version.rs), from the one file that sets it. Gradle reads
    // the same file for the APK's versionName and versionCode.
    println!("cargo:rerun-if-changed=android-port.properties");
    let revision = std::fs::read_to_string("android-port.properties")
        .ok()
        .and_then(|props| {
            props.lines().find_map(|line| {
                let (k, v) = line.split_once('=')?;
                (k.trim() == "revision").then(|| v.trim().to_string())
            })
        })
        .filter(|v| v.parse::<u32>().is_ok())
        .expect("android-port.properties must set revision=<number>");
    println!("cargo:rustc-env=LIMUSIC_ANDROID_REVISION={revision}");

    // tauri-build watches tauri.conf.json but not the icons it embeds, so editing a PNG here
    // leaves `generate_context!` emitting the old `default_window_icon` (window, tray, taskbar).
    println!("cargo:rerun-if-changed=icons");

    // Android links libmpv (and libavcodec, for `av_jni_set_java_vm`) from the jniLibs directory
    // that `scripts/android/fetch-libmpv.sh` fills, which is also what Gradle packages, so the
    // library linked against is the library shipped.
    if std::env::var("CARGO_CFG_TARGET_OS").as_deref() == Ok("android") {
        let abi = match std::env::var("CARGO_CFG_TARGET_ARCH").as_deref() {
            Ok("aarch64") => "arm64-v8a",
            Ok("arm") => "armeabi-v7a",
            Ok("x86_64") => "x86_64",
            Ok("x86") => "x86",
            other => panic!("unsupported Android architecture {other:?}"),
        };
        let dir = std::path::Path::new(&std::env::var("CARGO_MANIFEST_DIR").unwrap())
            .join("gen/android/app/src/main/jniLibs")
            .join(abi);
        if !dir.join("libmpv.so").exists() {
            panic!(
                "{} has no libmpv.so; run scripts/android/fetch-libmpv.sh {abi} first",
                dir.display()
            );
        }
        println!("cargo:rerun-if-changed={}", dir.join("libmpv.so").display());
        println!("cargo:rustc-link-search=native={}", dir.display());
        println!("cargo:rustc-link-lib=dylib=avcodec");
    }

    tauri_build::build()
}
