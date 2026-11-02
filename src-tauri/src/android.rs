//! Android glue: the JNI seam between the Rust core and the Kotlin side of the app
//! (`gen/android/app/src/main/java/com/limusic/android/`).
//!
//! Both directions are plain JNI, not a Tauri mobile plugin, on purpose. A plugin call is routed
//! through the activity's plugin manager and the webview's IPC, and the whole point of the media
//! session is to keep working when the activity is gone and the webview is paused: the lock screen
//! and a Bluetooth headset must still reach the player, and the notification must still hear about
//! the next track.
//!
//! * **Kotlin → Rust**: `NativeBridge.nativeAttach` (once, from `MainActivity.onCreate`, before the
//!   Tauri runtime starts) and `NativeBridge.nativeMediaCommand` (every transport press from the
//!   media session, audio focus and the becoming-noisy receiver). Commands go through
//!   [`crate::media::handle_event`], the same entry point MPRIS and SMTC use on the desktop.
//! * **Rust → Kotlin**: static methods on `NativeBridge`, called with the class reference cached at
//!   attach time. A thread Rust created cannot look an app class up by name (its `FindClass` sees
//!   the system class loader), so the cached `GlobalRef` is the only way in from one.

use std::ffi::{c_char, c_int, c_void, CString};
use std::io::Write;
use std::sync::{Mutex, OnceLock};
use std::time::Duration;

use jni::objects::{GlobalRef, JClass, JObject, JString, JValue, JValueOwned};
use jni::sys::{jdouble, jfloat};
use jni::{JNIEnv, JavaVM};
use souvlaki::{MediaControlEvent, MediaPosition};
use tauri::{AppHandle, Emitter};

static VM: OnceLock<JavaVM> = OnceLock::new();
/// `com.limusic.android.NativeBridge`.
static BRIDGE: OnceLock<GlobalRef> = OnceLock::new();
/// The application context handed to libavcodec. Held for the life of the process: FFmpeg keeps
/// the raw reference.
static APP_CONTEXT: OnceLock<GlobalRef> = OnceLock::new();
static APP: OnceLock<AppHandle> = OnceLock::new();

extern "C" {
    // libavcodec (shipped with libmpv). mpv's AudioTrack output and MediaCodec decoding reach the
    // JVM through these, so they must be set before the first track opens its audio device.
    fn av_jni_set_java_vm(vm: *mut c_void, log_ctx: *mut c_void) -> c_int;
    fn av_jni_set_android_app_ctx(app_ctx: *mut c_void, log_ctx: *mut c_void) -> c_int;
}

#[link(name = "log")]
extern "C" {
    fn __android_log_write(prio: c_int, tag: *const c_char, text: *const c_char) -> c_int;
}

/// Hand the app handle to the JNI entry points. Called from `setup`, before the player exists.
pub fn init(app: &AppHandle) {
    let _ = APP.set(app.clone());
    if VM.get().is_none() {
        // Without the attach the audio output cannot start, which would surface as every track
        // failing with "Couldn't start audio output". Say why here, where it can be found.
        tracing::error!("NativeBridge.nativeAttach never ran: mpv's AudioTrack output has no JVM");
    }
}

#[no_mangle]
pub extern "system" fn Java_com_limusic_android_NativeBridge_nativeAttach(
    env: JNIEnv,
    class: JClass,
    context: JObject,
) {
    if VM.get().is_some() {
        return; // A recreated activity; the process-wide state is already in place.
    }
    let Ok(vm) = env.get_java_vm() else { return };
    // SAFETY: both calls only store the pointers; the VM lives as long as the process and the
    // context reference is a global one kept in `APP_CONTEXT` for that long.
    unsafe {
        av_jni_set_java_vm(vm.get_java_vm_pointer().cast(), std::ptr::null_mut());
    }
    if let Ok(ctx) = env.new_global_ref(context) {
        unsafe {
            av_jni_set_android_app_ctx(ctx.as_obj().as_raw().cast(), std::ptr::null_mut());
        }
        let _ = APP_CONTEXT.set(ctx);
    }
    if let Ok(class) = env.new_global_ref(class) {
        let _ = BRIDGE.set(class);
    }
    let _ = VM.set(vm);
}

/// A transport command from the media session (notification, lock screen, headset, Bluetooth,
/// Android Auto), audio focus or the becoming-noisy receiver. `arg` is the seek target in
/// listening seconds for `seek`, and unused otherwise.
#[no_mangle]
pub extern "system" fn Java_com_limusic_android_NativeBridge_nativeMediaCommand(
    mut env: JNIEnv,
    _class: JClass,
    cmd: JString,
    arg: jdouble,
) {
    let Some(app) = APP.get() else { return };
    let Ok(cmd) = env.get_string(&cmd) else { return };
    let event = match cmd.to_str().unwrap_or_default() {
        "play" => return play(app),
        "pause" | "stop" => MediaControlEvent::Pause,
        "toggle" => MediaControlEvent::Toggle,
        "next" => MediaControlEvent::Next,
        "previous" => MediaControlEvent::Previous,
        "seek" if arg.is_finite() && arg >= 0.0 => {
            MediaControlEvent::SetPosition(MediaPosition(Duration::from_secs_f64(arg)))
        }
        other => {
            tracing::warn!(command = other, "unknown media command from the session");
            return;
        }
    };
    crate::media::handle_event(app, event);
}

/// Limusic was swiped out of Recents: the user closed it. Stop the music and save where it was,
/// as quitting the desktop app does (`RunEvent::Exit`), before `PlaybackService` ends the process.
/// Synchronous on purpose: the caller kills the process as soon as this returns.
#[no_mangle]
pub extern "system" fn Java_com_limusic_android_NativeBridge_nativeQuit(
    _env: JNIEnv,
    _class: JClass,
) {
    use tauri::Manager;
    let Some(app) = APP.get() else { return };
    let Some(state) = app.try_state::<std::sync::Arc<crate::state::AppState>>() else { return };
    let _ = state.player.pause();
    state.flush_position();
}

/// Play, never toggle. `media::handle_event` routes `Play` to `resume_or_toggle`, which pauses
/// when something is already playing; MediaSession sends a play for KEYCODE_MEDIA_PLAY, a
/// headset's play button and an audio-focus regain, none of which may ever pause. Idle with a
/// restored queue, it starts the current track like the UI's play button does.
fn play(app: &AppHandle) {
    use tauri::Manager;
    let app = app.clone();
    tauri::async_runtime::spawn(async move {
        let Some(state) = app.try_state::<std::sync::Arc<crate::state::AppState>>() else { return };
        let state = state.inner().clone();
        if state.lt.is_guest().await {
            return; // guest playback is host-driven
        }
        if state.player.is_idle() {
            state.resume_or_toggle().await;
        } else {
            let _ = state.player.play();
        }
    });
}

/// An argument to a `NativeBridge` method, as Rust holds it. Converted to its JNI form inside the
/// call's local frame, so no local reference outlives the call.
enum Arg<'a> {
    Str(Option<&'a str>),
    Bool(bool),
    Double(f64),
}

/// The system bars, display cutout and keyboard, in CSS pixels: top, right, bottom, left, then the
/// keyboard's own height (already part of bottom).
static INSETS: Mutex<[f32; 5]> = Mutex::new([0.0; 5]);

/// Where the page must not put anything it wants seen or touched (`commands::window_insets`).
pub fn insets() -> [f32; 5] {
    *INSETS.lock().unwrap()
}

/// The activity is edge to edge (mandatory at targetSdk 35+), so the SPA pads itself by these. Sent
/// on every change: rotation, a DeX window moving between displays, the keyboard opening.
#[no_mangle]
pub extern "system" fn Java_com_limusic_android_NativeBridge_nativeInsets(
    _env: JNIEnv,
    _class: JClass,
    top: jfloat,
    right: jfloat,
    bottom: jfloat,
    left: jfloat,
    keyboard: jfloat,
) {
    let new = [top, right, bottom, left, keyboard];
    let changed = {
        let mut cur = INSETS.lock().unwrap();
        std::mem::replace(&mut *cur, new) != new
    };
    if changed {
        if let Some(app) = APP.get() {
            let _ = app.emit_to("main", "window-insets", new);
        }
    }
}

/// Call `NativeBridge.<name>` from any thread. Failures are logged and swallowed: a missing
/// notification update must never take playback down with it.
fn call(name: &str, sig: &str, args: &[Arg]) {
    call_with(name, sig, args, |_, _| Ok(()));
}

/// `call` for a method that answers: `read` turns the result into Rust inside the call's local
/// frame. `None` when the bridge isn't up or the call failed (logged).
fn call_with<T>(
    name: &str,
    sig: &str,
    args: &[Arg],
    read: impl FnOnce(&mut JNIEnv, JValueOwned) -> jni::errors::Result<T>,
) -> Option<T> {
    let (Some(vm), Some(class)) = (VM.get(), BRIDGE.get()) else { return None };
    // Permanent: the callers are the long-lived media-controls thread and tokio workers, and an
    // attach per call costs a JNIEnv setup every position tick.
    let Ok(mut env) = vm.attach_current_thread_permanently() else { return None };
    let result = env.with_local_frame(8, |env| -> jni::errors::Result<T> {
        let mut strings = Vec::new();
        for a in args {
            if let Arg::Str(Some(s)) = a {
                strings.push(JObject::from(env.new_string(s)?));
            }
        }
        let mut strings = strings.iter();
        let null = JObject::null();
        let values: Vec<JValue> = args
            .iter()
            .map(|a| match a {
                Arg::Str(Some(_)) => JValue::Object(strings.next().unwrap_or(&null)),
                Arg::Str(None) => JValue::Object(&null),
                Arg::Bool(b) => JValue::Bool(u8::from(*b)),
                Arg::Double(d) => JValue::Double(*d),
            })
            .collect();
        let class: &JClass = class.as_obj().into();
        let answer = env.call_static_method(class, name, sig, &values)?;
        read(env, answer)
    });
    match result {
        Ok(v) => Some(v),
        Err(e) => {
            if env.exception_check().unwrap_or(false) {
                let _ = env.exception_describe();
                let _ = env.exception_clear();
            }
            tracing::warn!(method = name, error = %e, "NativeBridge call failed");
            None
        }
    }
}

// Files from the system pickers. On Android the dialog plugin answers with a `content://` URI, not
// a path: the document may live in Downloads, on a drive or in another app, and only the
// ContentResolver can open it. The commands that read a picked file take it through
// `copy_content` (so everything after keeps working on a real path), the one that writes one
// through `write_content`.

/// The picked document, opened as a file this process owns.
fn open_content(uri: &str, mode: &str) -> Result<std::fs::File, String> {
    use std::os::fd::FromRawFd;
    let fd = call_with(
        "openContent",
        "(Ljava/lang/String;Ljava/lang/String;)I",
        &[Arg::Str(Some(uri)), Arg::Str(Some(mode))],
        |_, v| v.i(),
    )
    .unwrap_or(-1);
    if fd < 0 {
        return Err("The file couldn't be opened.".into());
    }
    // SAFETY: `detachFd` handed this descriptor over; nothing on the Java side closes it now.
    Ok(unsafe { std::fs::File::from_raw_fd(fd) })
}

/// The name the picker showed for it, reduced to a bare file name.
fn content_name(uri: &str) -> Option<String> {
    let name = call_with(
        "contentName",
        "(Ljava/lang/String;)Ljava/lang/String;",
        &[Arg::Str(Some(uri))],
        |env, v| {
            let o = v.l()?;
            if o.is_null() {
                return Ok(None);
            }
            Ok(Some(String::from(env.get_string(&JString::from(o))?)))
        },
    )
    .flatten()?;
    let name = name.rsplit(['/', '\\']).next().unwrap_or_default().trim().to_owned();
    (!name.is_empty() && name != "." && name != "..").then_some(name)
}

/// Copy a picked document into `dir` under its own name and answer that path. A plain path (not
/// `content://`) is answered as it is.
pub fn copy_content(uri: &str, dir: &std::path::Path) -> Result<String, String> {
    if !uri.starts_with("content://") {
        return Ok(uri.to_owned());
    }
    let name = content_name(uri).unwrap_or_else(|| "picked".into());
    std::fs::create_dir_all(dir).map_err(|e| e.to_string())?;
    let dest = dir.join(name);
    let mut src = open_content(uri, "r")?;
    let mut out = std::fs::File::create(&dest).map_err(|e| e.to_string())?;
    std::io::copy(&mut src, &mut out).map_err(|e| e.to_string())?;
    Ok(dest.to_string_lossy().into_owned())
}

/// A picked document's bytes and file name (for the commands that only read it once).
pub fn read_content(uri: &str) -> Result<(Vec<u8>, String), String> {
    use std::io::Read;
    let mut bytes = Vec::new();
    open_content(uri, "r")?.read_to_end(&mut bytes).map_err(|e| e.to_string())?;
    Ok((bytes, content_name(uri).unwrap_or_default()))
}

/// Write `bytes` to the document a save picker chose (or to a plain path), replacing what was there.
pub fn write_content(uri: &str, bytes: &[u8]) -> Result<(), String> {
    if !uri.starts_with("content://") {
        return std::fs::write(uri, bytes).map_err(|e| e.to_string());
    }
    open_content(uri, "wt")?.write_all(bytes).map_err(|e| e.to_string())
}

const STR: &str = "Ljava/lang/String;";

pub fn media_metadata(title: &str, artist: &str, album: Option<&str>, cover: Option<&str>) {
    call(
        "mediaMetadata",
        &format!("({STR}{STR}{STR}{STR})V"),
        &[Arg::Str(Some(title)), Arg::Str(Some(artist)), Arg::Str(album), Arg::Str(cover)],
    );
}

/// A track is being resolved and will play once it is: the session shows it as buffering with
/// play-when-ready set. Media3 runs its service in the foreground from that state, so the service
/// goes foreground while the user is still in the app. Waiting for the stream instead (seconds on
/// a cold start) put that request in the background whenever the user left at once, where Android
/// 12+ refuses it, and a process without a foreground service is frozen with the music in it.
pub fn media_loading(title: &str, artist: &str, album: Option<&str>, cover: Option<&str>) {
    call(
        "mediaLoading",
        &format!("({STR}{STR}{STR}{STR})V"),
        &[Arg::Str(Some(title)), Arg::Str(Some(artist)), Arg::Str(album), Arg::Str(cover)],
    );
}

/// The track `media_loading` announced is not going to play.
pub fn media_loading_cancelled() {
    call("mediaLoadingCancelled", "()V", &[]);
}

pub fn media_album(album: &str) {
    call("mediaAlbum", &format!("({STR})V"), &[Arg::Str(Some(album))]);
}

/// Track length in listening seconds (already divided by the tempo, see `media.rs`).
pub fn media_duration(secs: f64) {
    call("mediaDuration", "(D)V", &[Arg::Double(secs)]);
}

/// Play state and position in listening seconds. The session extrapolates between these.
pub fn media_playback(playing: bool, pos: f64) {
    call("mediaPlayback", "(ZD)V", &[Arg::Bool(playing), Arg::Double(pos)]);
}

/// The session ended (`AppState::dismiss_session`): the media session goes idle and Media3 takes
/// the notification down.
pub fn media_clear() {
    call("mediaClear", "()V", &[]);
}

/// Theater mode's fullscreen: hide or restore the system bars.
pub fn set_immersive(on: bool) {
    call("setImmersive", "(Z)V", &[Arg::Bool(on)]);
}

/// Open `SignInActivity`: Google's own sign-in page in a WebView of its own (see that class). The
/// cookies it ends with come back through `nativeSignInCookie`. `add_account` empties that
/// WebView's jar first and opens Google's AddSession screen, so the new sign-in can't continue
/// into the account it last held.
pub fn open_sign_in(add_account: bool) -> Result<(), String> {
    if VM.get().is_none() {
        return Err("The Android bridge isn't attached".into());
    }
    call("openSignIn", "(Z)V", &[Arg::Bool(add_account)]);
    Ok(())
}

/// An account was removed: clear the Google session `SignInActivity`'s WebView profile still holds
/// from signing it in (see `SignInActivity.forget`).
pub fn forget_sign_in() {
    call("forgetSignIn", "()V", &[]);
}

/// The `Cookie` header `SignInActivity` read for music.youtube.com once Google's sign-in landed
/// there. It goes through the same `AppState::sign_in` as the desktop's sign-in window and the
/// cookie paste: validated against YouTube before anything is kept, rolled back on failure, and on
/// to the channel picker for a multi-channel account. The activity waits on `signInFinished`.
///
/// The value is a credential: it is never logged, here or on the Kotlin side.
#[no_mangle]
pub extern "system" fn Java_com_limusic_android_NativeBridge_nativeSignInCookie(
    mut env: JNIEnv,
    _class: JClass,
    cookie: JString,
) {
    let cookie: String = match env.get_string(&cookie) {
        Ok(s) => s.into(),
        Err(_) => return sign_in_finished(false, Some("Couldn't read the session")),
    };
    let Some(app) = APP.get().cloned() else {
        return sign_in_finished(false, Some("Limusic hasn't finished starting"));
    };
    tauri::async_runtime::spawn(async move {
        use tauri::Manager;
        let Some(state) = app.try_state::<std::sync::Arc<crate::state::AppState>>() else {
            return sign_in_finished(false, Some("Limusic hasn't finished starting"));
        };
        let state = state.inner().clone();
        match state.sign_in(cookie, None).await {
            Ok(crate::state::SignInOutcome::Complete) => {
                let _ = app.emit("login-done", ());
                sign_in_finished(true, None);
            }
            // Saved but unfinished until the main window's picker chooses a channel, exactly as
            // after the desktop's sign-in window.
            Ok(crate::state::SignInOutcome::SelectionRequired) => sign_in_finished(true, None),
            Err(e) => {
                let _ = app.emit("login-error", &e);
                sign_in_finished(false, Some(&e));
            }
        }
    });
}

/// Tell `SignInActivity` how validation went: it closes on success and shows `message` otherwise.
fn sign_in_finished(ok: bool, message: Option<&str>) {
    call("signInFinished", &format!("(Z{STR})V"), &[Arg::Bool(ok), Arg::Str(message)]);
}

/// How Android's folder picker ended (`pick_folder`).
#[derive(serde::Serialize)]
#[serde(tag = "status", rename_all = "snake_case")]
pub enum FolderPick {
    /// A folder on shared storage, as a filesystem path the scanner and mpv can read.
    Picked {
        path: String,
    },
    Cancelled,
    /// The audio-files permission was refused (or dismissed).
    Denied,
    /// A place with no filesystem path (a cloud provider, the Downloads app's own list).
    Unsupported,
}

/// The pick in flight: one at a time, a second asking while one is open replaces it.
static FOLDER: Mutex<Option<tokio::sync::oneshot::Sender<FolderPick>>> = Mutex::new(None);

/// Ask for the audio-files permission if it isn't held, then open the system folder picker
/// (`MainActivity.pickFolder`). The dialog plugin's folder picker is desktop-only.
pub async fn pick_folder() -> Result<FolderPick, String> {
    if VM.get().is_none() {
        return Err("The Android bridge isn't attached".into());
    }
    let (tx, rx) = tokio::sync::oneshot::channel();
    *FOLDER.lock().unwrap() = Some(tx);
    call("pickFolder", "()V", &[]);
    // Replaced by a newer pick: that one answers instead.
    rx.await.map_err(|_| "The folder picker closed".to_string())
}

#[no_mangle]
pub extern "system" fn Java_com_limusic_android_NativeBridge_nativeFolderPicked(
    mut env: JNIEnv,
    _class: JClass,
    status: JString,
    path: JString,
) {
    let status: String = env.get_string(&status).map(Into::into).unwrap_or_default();
    let path: Option<String> =
        if path.is_null() { None } else { env.get_string(&path).ok().map(Into::into) };
    let pick = match (status.as_str(), path) {
        ("picked", Some(path)) => FolderPick::Picked { path },
        ("denied", _) => FolderPick::Denied,
        ("unsupported", _) => FolderPick::Unsupported,
        _ => FolderPick::Cancelled,
    };
    if let Some(tx) = FOLDER.lock().unwrap().take() {
        let _ = tx.send(pick);
    }
}

/// Whether the app may read audio files on shared storage, as the activity last saw it (it checks
/// on every resume, so a grant or revoke in Settings shows up on return). `None` until then.
static AUDIO_ACCESS: Mutex<Option<bool>> = Mutex::new(None);

pub fn audio_access() -> Option<bool> {
    *AUDIO_ACCESS.lock().unwrap()
}

#[no_mangle]
pub extern "system" fn Java_com_limusic_android_NativeBridge_nativeAudioAccess(
    _env: JNIEnv,
    _class: JClass,
    granted: jni::sys::jboolean,
) {
    let granted = granted != 0;
    let changed = AUDIO_ACCESS.lock().unwrap().replace(granted) != Some(granted);
    if changed {
        if let Some(app) = APP.get() {
            let _ = app.emit_to("main", "audio-access", granted);
        }
    }
}

/// The app's page in Android's Settings, where a refused permission can be turned back on.
pub fn open_app_settings() {
    call("openAppSettings", "()V", &[]);
}

/// Open an http(s) link with whatever handles it (`ACTION_VIEW`).
pub fn open_url(url: &str) -> Result<(), std::io::Error> {
    if VM.get().is_none() {
        return Err(std::io::Error::other("the Android bridge isn't attached"));
    }
    call("openUrl", &format!("({STR})V"), &[Arg::Str(Some(url))]);
    Ok(())
}

/// A `tracing` writer into logcat (tag `limusic`). Lines are buffered until their newline, since
/// each `__android_log_write` is one logcat entry.
pub struct Logcat;

impl<'a> tracing_subscriber::fmt::MakeWriter<'a> for Logcat {
    type Writer = LogcatLine;
    fn make_writer(&'a self) -> Self::Writer {
        LogcatLine(Vec::with_capacity(256))
    }
}

pub struct LogcatLine(Vec<u8>);

impl Write for LogcatLine {
    fn write(&mut self, buf: &[u8]) -> std::io::Result<usize> {
        self.0.extend_from_slice(buf);
        Ok(buf.len())
    }

    fn flush(&mut self) -> std::io::Result<()> {
        Ok(())
    }
}

impl Drop for LogcatLine {
    fn drop(&mut self) {
        static TAG: &std::ffi::CStr = c"limusic";
        // ANDROID_LOG_INFO. The level is already in the formatted line, and one priority keeps
        // `adb logcat -s limusic` showing everything the file log would.
        const INFO: c_int = 4;
        static LOCK: Mutex<()> = Mutex::new(());
        let text = String::from_utf8_lossy(&self.0);
        let text = text.trim_end();
        if text.is_empty() {
            return;
        }
        let Ok(line) = CString::new(text.replace('\0', "")) else { return };
        let _guard = LOCK.lock();
        // SAFETY: both pointers are valid NUL-terminated strings for the duration of the call.
        unsafe { __android_log_write(INFO, TAG.as_ptr(), line.as_ptr()) };
    }
}
