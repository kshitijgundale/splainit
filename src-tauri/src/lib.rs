use serde::{Deserialize, Serialize};
use std::ffi::{c_char, CStr, CString};
use std::str::FromStr;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex};
use std::time::{SystemTime, UNIX_EPOCH};
use tokio::sync::watch;
use tauri::{Emitter, Manager};
use tauri_plugin_global_shortcut::{Code, GlobalShortcutExt, Modifiers, Shortcut, ShortcutState};

mod prompts;
mod openai;
mod history;
mod capture;
mod updates;
use updates::{check_for_updates, install_update, UpdateState};
use capture::{Capture, CaptureMethod, CaptureStatus, NativeCapture};

unsafe extern "C" {
    fn splainit_set_invocation(invocation: u64);
    fn splainit_frontmost() -> *mut c_char;
    fn splainit_accessibility_granted() -> bool;
    fn splainit_request_accessibility() -> bool;
    fn splainit_request_screen_recording() -> bool;
    fn splainit_capture(pid: i32, with_context: bool, invocation: u64) -> *mut c_char;
    fn splainit_drag_capture(invocation: u64) -> *mut c_char;
    fn splainit_free(pointer: *mut c_char);
    fn splainit_activate();
    fn splainit_load_shortcut() -> *mut c_char;
    fn splainit_save_shortcut(value: *const c_char);
    fn splainit_excluded_apps() -> *mut c_char;
    fn splainit_save_excluded_apps(value: *const c_char);
    fn splainit_is_excluded(bundle_id: *const c_char) -> bool;
    fn splainit_store_api_key(value: *const c_char) -> i32;
    fn splainit_has_api_key() -> bool;
    fn splainit_read_api_key() -> *mut c_char;
    fn splainit_free_api_key(pointer: *mut c_char);
    fn splainit_remove_api_key() -> i32;
    fn splainit_context_enabled() -> bool;
    fn splainit_set_context_enabled(enabled: bool);
    fn splainit_load_model() -> *mut c_char;
    fn splainit_save_model(value: *const c_char);
    fn splainit_history_enabled() -> bool;
    fn splainit_set_history_enabled(enabled: bool);
}

#[derive(Clone, Deserialize)]
struct Source {
    pid: i32,
    source_app: String,
    bundle_id: String,
}

fn is_current(generation: &AtomicU64, invocation: u64) -> bool {
    generation.load(Ordering::SeqCst) == invocation
}

fn source_is_blocked(bundle_id: &str, excluded: bool) -> bool {
    bundle_id.is_empty() || bundle_id == "app.splainit.desktop" || excluded
}

#[derive(Deserialize)]
struct ExcludedApps {
    apps: Vec<String>,
}

struct AppState {
    generation: AtomicU64,
    request_generation: AtomicU64,
    cancel_tx: watch::Sender<u64>,
    latest: Mutex<Option<Capture>>,
    shortcut_status: Mutex<String>,
    shortcut: Mutex<(Shortcut, bool)>,
}

fn native_json<T: for<'de> Deserialize<'de>>(raw: *mut c_char) -> Result<T, String> {
    if raw.is_null() {
        return Err("Native capture returned no data".into());
    }
    let value = unsafe { CStr::from_ptr(raw).to_bytes().to_vec() };
    unsafe { splainit_free(raw) };
    serde_json::from_slice(&value).map_err(|_| "Native capture returned invalid data".into())
}

fn begin_capture(app: tauri::AppHandle, state: Arc<AppState>) {
    // Snapshot the frontmost process synchronously while it still owns focus.
    let source: Result<Source, _> = native_json(unsafe { splainit_frontmost() });
    let invocation = {
        let _latest = state.latest.lock().unwrap();
        let next = state.generation.fetch_add(1, Ordering::SeqCst) + 1;
        unsafe { splainit_set_invocation(next) };
        next
    };
    let cancelled = state.request_generation.fetch_add(1, Ordering::SeqCst) + 1;
    state.cancel_tx.send_replace(cancelled);
    let timestamp_ms = SystemTime::now().duration_since(UNIX_EPOCH).unwrap_or_default().as_millis();
    std::thread::spawn(move || {
        let capture = match source {
            Ok(source) => {
                let excluded = CString::new(source.bundle_id.as_str())
                    .map(|id| unsafe { splainit_is_excluded(id.as_ptr()) })
                    .unwrap_or(true);
                let with_context = unsafe { splainit_context_enabled() };
                let result: Result<NativeCapture, _> = if source_is_blocked(&source.bundle_id, excluded) {
                    Ok(NativeCapture::failure(CaptureStatus::Blocked, "Source application is excluded or unidentified"))
                } else {
                    native_json(unsafe { splainit_capture(source.pid, with_context, invocation) })
                };
                let result = result.unwrap_or_else(|detail| NativeCapture::failure(CaptureStatus::Failed, detail))
                    .checked(with_context);
                Capture { invocation, timestamp_ms, revision: 0, source_app: source.source_app,
                    bundle_id: source.bundle_id, pid: source.pid, result }
            }
            Err(detail) => Capture { invocation, timestamp_ms, revision: 0, source_app: String::new(),
                bundle_id: String::new(), pid: 0,
                result: NativeCapture::failure(CaptureStatus::Failed, detail) },
        };
        publish_capture(app, state, capture);
    });
}

fn publish_capture(app: tauri::AppHandle, state: Arc<AppState>, capture: Capture) {
    let invocation = capture.invocation;
        if !is_current(&state.generation, invocation) {
            return;
        }
        {
            let mut latest = state.latest.lock().unwrap();
            if !is_current(&state.generation, invocation) { return; }
            *latest = Some(capture.clone());
        }
        // AppKit window operations must run on the main thread. The source was
        // already snapshotted and AX queried before this is dispatched.
        let ui_app = app.clone();
        if let Err(error) = app.run_on_main_thread(move || {
            if !is_current(&state.generation, invocation) {
                return;
            }
            if let Some(window) = ui_app.get_webview_window("main") {
                if let Err(error) = window.show() {
                    eprintln!("capture window show failed: {error}");
                }
                unsafe { splainit_activate() };
                if let Err(error) = window.set_focus() {
                    eprintln!("capture window focus failed: {error}");
                }
            } else {
                eprintln!("capture window missing");
            }
            if let Some(window) = ui_app.get_webview_window("main") {
                let _ = window.emit("capture", capture);
            }
        }) {
            eprintln!("capture window dispatch failed: {error}");
        }

}

#[tauri::command]
async fn drag_capture(app: tauri::AppHandle, state: tauri::State<'_, Arc<AppState>>, invocation: u64) -> Result<Capture, String> {
    let state = state.inner().clone();
    let mut capture = {
        let mut latest = state.latest.lock().unwrap();
        let snapshot = latest.as_mut().ok_or("No selection is available")?;
        if !is_current(&state.generation, invocation) || snapshot.invocation != invocation ||
            snapshot.status != CaptureStatus::Unavailable || !snapshot.visual_available {
            return Err("Drag to explain is unavailable for this capture".into());
        }
        snapshot.result.visual_available = false;
        snapshot.clone()
    };
    let (hidden_tx, hidden_rx) = tokio::sync::oneshot::channel();
    let ui_app = app.clone();
    app.run_on_main_thread(move || {
        if let Some(window) = ui_app.get_webview_window("main") { let _ = window.hide(); }
        if let Some(window) = ui_app.get_webview_window("settings") { let _ = window.hide(); }
        let _ = hidden_tx.send(());
    }).map_err(|_| "Could not prepare visual selection")?;
    hidden_rx.await.map_err(|_| "Could not hide the reply panel")?;
    let result: Result<NativeCapture, String> = tauri::async_runtime::spawn_blocking(move ||
        native_json(unsafe { splainit_drag_capture(invocation) }))
        .await.map_err(|_| "Visual capture worker stopped")?;
    capture.result = result.unwrap_or_else(|error| NativeCapture::failure(CaptureStatus::Failed, error)).checked(false);
    capture.revision += 1;
    if !is_current(&state.generation, invocation) { return Err("Visual capture was superseded".into()); }
    publish_capture(app, state, capture.clone());
    Ok(capture)
}

#[tauri::command]
fn latest_capture(state: tauri::State<'_, Arc<AppState>>) -> Option<Capture> {
    state.latest.lock().unwrap().clone()
}

#[tauri::command]
fn shortcut_status(state: tauri::State<'_, Arc<AppState>>) -> String {
    state.shortcut_status.lock().unwrap().clone()
}

#[tauri::command]
fn current_shortcut(state: tauri::State<'_, Arc<AppState>>) -> String {
    state.shortcut.lock().unwrap().0.to_string()
}

#[tauri::command]
fn get_excluded_apps() -> Result<Vec<String>, String> {
    let result: ExcludedApps = native_json(unsafe { splainit_excluded_apps() })?;
    Ok(result.apps)
}

#[tauri::command]
fn set_excluded_apps(apps: Vec<String>) -> Result<(), String> {
    if apps.len() > 64 || apps.iter().any(|id| {
        id.len() > 255 || id.len() < 3 || !id.contains('.') ||
        id.split('.').any(|part| part.is_empty()) ||
        !id.bytes().all(|byte| byte.is_ascii_alphanumeric() || byte == b'.' || byte == b'-')
    }) {
        return Err("Enter up to 64 valid application bundle IDs".into());
    }
    let value = CString::new(serde_json::to_string(&apps).map_err(|_| "Invalid exclusion list".to_string())?)
        .map_err(|_| "Invalid exclusion list".to_string())?;
    unsafe { splainit_save_excluded_apps(value.as_ptr()) };
    Ok(())
}

#[tauri::command]
fn api_key_configured() -> bool {
    unsafe { splainit_has_api_key() }
}

#[tauri::command]
fn accessibility_granted() -> bool {
    unsafe { splainit_accessibility_granted() }
}

#[tauri::command]
fn request_accessibility() -> bool {
    unsafe { splainit_request_accessibility() }
}

#[tauri::command]
fn recover_capture_permission(state: tauri::State<'_, Arc<AppState>>, invocation: u64) -> Result<bool, String> {
    let kind = {
        let latest = state.latest.lock().unwrap();
        let capture = latest.as_ref().ok_or("No capture requires permission")?;
        if !is_current(&state.generation, invocation) || capture.invocation != invocation || capture.status != CaptureStatus::PermissionRequired {
            return Err("No current capture requires permission".into());
        }
        capture.permission.as_ref().ok_or("Required permission is unknown")?.kind
    };
    let granted = unsafe { match kind {
        capture::PermissionKind::Accessibility => splainit_request_accessibility(),
        capture::PermissionKind::ScreenRecording => splainit_request_screen_recording(),
    } };
    if !granted {
        let mut latest = state.latest.lock().unwrap();
        if let Some(capture) = latest.as_mut() {
            if capture.invocation == invocation && is_current(&state.generation, invocation) {
                if let Some(permission) = capture.result.permission.as_mut() {
                    permission.state = capture::PermissionState::Denied;
                }
            }
        }
    }
    Ok(granted)
}

#[tauri::command]
fn show_settings(app: tauri::AppHandle) {
    let ui_app = app.clone();
    let _ = app.run_on_main_thread(move || {
        if let Some(window) = ui_app.get_webview_window("settings") {
            let _ = window.show();
            let _ = window.set_focus();
        }
    });
}

#[tauri::command]
fn hide_current_window(window: tauri::WebviewWindow) {
    let _ = window.hide();
}

#[tauri::command]
fn context_enabled() -> bool {
    unsafe { splainit_context_enabled() }
}

#[tauri::command]
fn get_presets() -> Vec<prompts::PresetInfo> {
    prompts::presets()
}

#[tauri::command]
fn set_context_enabled(enabled: bool) {
    unsafe { splainit_set_context_enabled(enabled) };
}

fn saved_model() -> String {
    let raw = unsafe { splainit_load_model() };
    if raw.is_null() { return openai::default_model().into() }
    let model = unsafe { CStr::from_ptr(raw).to_string_lossy().into_owned() };
    unsafe { splainit_free(raw) };
    model
}

#[tauri::command]
fn get_model() -> String {
    saved_model()
}

#[tauri::command]
fn history_enabled() -> bool {
    unsafe { splainit_history_enabled() }
}

#[tauri::command]
fn set_history_enabled(enabled: bool) {
    unsafe { splainit_set_history_enabled(enabled) };
}

#[tauri::command]
fn list_history(app: tauri::AppHandle, query: String, offset: u32) -> Result<Vec<history::HistoryRecord>, String> {
    history::list(&app, &query, offset)
}

#[tauri::command]
fn delete_history_entry(app: tauri::AppHandle, id: i64) -> Result<bool, String> {
    history::delete(&app, id)
}

#[tauri::command]
fn clear_history(app: tauri::AppHandle) -> Result<(), String> {
    history::clear(&app)
}

#[tauri::command]
fn set_model(value: String) -> Result<(), String> {
    if value.is_empty() || value.len() > 100 ||
        !value.bytes().all(|byte| byte.is_ascii_alphanumeric() || matches!(byte, b'-' | b'_' | b'.' | b':')) {
        return Err("Enter a valid OpenAI model ID".into());
    }
    let native = CString::new(value).map_err(|_| "Enter a valid OpenAI model ID".to_string())?;
    unsafe { splainit_save_model(native.as_ptr()) };
    Ok(())
}

#[tauri::command]
fn save_api_key(value: String) -> Result<(), String> {
    let value = value.trim();
    if value.len() < 8 || value.len() > 512 || value.chars().any(char::is_control) {
        return Err("Enter a valid API key".into());
    }
    let native = CString::new(value).map_err(|_| "Enter a valid API key".to_string())?;
    match unsafe { splainit_store_api_key(native.as_ptr()) } {
        0 => Ok(()),
        _ => Err("Could not save the API key to macOS Keychain".into()),
    }
}

#[tauri::command]
fn remove_api_key() -> Result<(), String> {
    match unsafe { splainit_remove_api_key() } {
        0 => Ok(()),
        _ => Err("Could not remove the API key from macOS Keychain".into()),
    }
}

// Only native request code may call this. No IPC command exposes the credential.
#[allow(dead_code)]
fn read_api_key_for_native_request() -> Option<String> {
    let raw = unsafe { splainit_read_api_key() };
    if raw.is_null() {
        return None;
    }
    let value = unsafe { CStr::from_ptr(raw).to_string_lossy().into_owned() };
    unsafe { splainit_free_api_key(raw) };
    Some(value)
}

#[derive(Serialize)]
struct Explanation {
    invocation: u64,
    preset_id: prompts::PresetId,
    preset_version: u32,
    model: String,
    response: String,
    history_saved: bool,
}

#[tauri::command]
async fn explain_capture(
    app: tauri::AppHandle,
    state: tauri::State<'_, Arc<AppState>>,
    invocation: u64,
    preset_id: prompts::PresetId,
    confirmed: bool,
) -> Result<Explanation, String> {
    let state = state.inner().clone();
    if !is_current(&state.generation, invocation) {
        return Err("This selection was superseded".into());
    }
    let mut capture = state.latest.lock().unwrap().clone().ok_or("No captured selection")?;
    if capture.invocation != invocation || !capture.can_explain(confirmed) {
        return Err("The captured text requires a verified selection or explicit confirmation".into());
    }
    if !unsafe { splainit_context_enabled() } {
        capture.result.context_before.clear();
        capture.result.context_after.clear();
    }
    let prompt = prompts::compose(preset_id, &capture.text, &capture.context_before, &capture.context_after)?;
    let key = read_api_key_for_native_request().ok_or("Add an OpenAI API key in settings to explain this selection")?;
    let model = saved_model();
    let request_id = state.request_generation.fetch_add(1, Ordering::SeqCst) + 1;
    state.cancel_tx.send_replace(request_id);
    let cancelled = state.cancel_tx.subscribe();
    let response = openai::explain(key, &model, &prompt, cancelled).await?;
    if !is_current(&state.generation, invocation) ||
        state.request_generation.load(Ordering::SeqCst) != request_id {
        return Err("This explanation was superseded".into());
    }
    // Serialize the final generation check and history write with new invocations.
    // Otherwise a shortcut could supersede this response during SQLite insertion.
    let _latest = state.latest.lock().unwrap();
    if !is_current(&state.generation, invocation) ||
        state.request_generation.load(Ordering::SeqCst) != request_id {
        return Err("This explanation was superseded".into());
    }
    let history_saved = if unsafe { splainit_history_enabled() } {
        let record = history::HistoryRecord {
            id: 0,
            created_at_ms: SystemTime::now().duration_since(UNIX_EPOCH).unwrap_or_default().as_millis() as i64,
            source_app: capture.source_app.clone(),
            bundle_id: capture.bundle_id.clone(),
            capture_method: capture.method.map(CaptureMethod::as_str).unwrap_or("unknown").into(),
            selected_text: capture.text.clone(),
            context_before: capture.context_before.clone(),
            context_after: capture.context_after.clone(),
            preset_id: preset_id.as_str().into(),
            preset_version: prompt.version as i64,
            prompt_text: prompt.instruction.into(),
            model_id: model.clone(),
            reply: response.clone(),
        };
        history::insert(&app, &record).is_ok()
    } else { false };
    Ok(Explanation { invocation, preset_id, preset_version: prompt.version, model, response, history_saved })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn terminal_capture_does_not_fall_through() {
        for status in [CaptureStatus::NoSelection, CaptureStatus::Blocked,
                       CaptureStatus::PermissionRequired, CaptureStatus::TimedOut,
                       CaptureStatus::Oversized, CaptureStatus::Cancelled, CaptureStatus::Failed] {
            assert!(!NativeCapture::failure(status, "fixture").can_explain(true));
        }
    }

    #[test]
    fn excluded_and_unidentified_sources_are_blocked_before_capture() {
        assert!(source_is_blocked("com.example.Private", true));
        assert!(source_is_blocked("", false));
        assert!(source_is_blocked("app.splainit.desktop", false));
        assert!(!source_is_blocked("com.apple.TextEdit", false));
    }

    #[test]
    fn secure_denied_empty_and_failed_visual_results_cannot_send_or_keep_text() {
        for status in [CaptureStatus::Blocked, CaptureStatus::PermissionRequired,
                       CaptureStatus::NoSelection, CaptureStatus::Cancelled,
                       CaptureStatus::TimedOut, CaptureStatus::Oversized, CaptureStatus::Failed] {
            let capture = NativeCapture {
                status, method: Some(CaptureMethod::VisualDragOcr),
                verification: capture::Verification::Unverified,
                text: "must not escape".into(),
                context_before: "private context".into(),
                ..NativeCapture::default()
            }.checked(true);
            assert!(!capture.can_explain(true));
            assert!(capture.text.is_empty());
            assert!(capture.context_before.is_empty());
        }
    }

    #[test]
    fn newer_capture_supersedes_older_generation() {
        let generation = AtomicU64::new(1);
        assert!(is_current(&generation, 1));
        generation.fetch_add(1, Ordering::SeqCst);
        assert!(!is_current(&generation, 1));
        assert!(is_current(&generation, 2));
    }

    #[test]
    fn exposed_payload_and_capabilities_do_not_include_credential_read() {
        let capture = Capture {
            invocation: 1, timestamp_ms: 1, revision: 0,
            source_app: "TextEdit".into(), bundle_id: "com.apple.TextEdit".into(), pid: 123,
            result: NativeCapture { status: CaptureStatus::Verified,
                method: Some(CaptureMethod::AxSelectedText), verification: capture::Verification::Semantic,
                text: "sample".into(), ..NativeCapture::default() },
        };
        let payload = serde_json::to_value(capture).unwrap();
        assert!(payload.get("api_key").is_none());
        let panel = include_str!("../capabilities/panel.json");
        let settings = include_str!("../capabilities/settings.json");
        let manifest = include_str!("../build.rs");
        for source in [panel, settings, manifest] {
            assert!(!source.contains("read_api_key"));
        }
    }
}

#[tauri::command]
fn cancel_explanation(state: tauri::State<'_, Arc<AppState>>) {
    let value = state.request_generation.fetch_add(1, Ordering::SeqCst) + 1;
    state.cancel_tx.send_replace(value);
}

#[tauri::command]
fn dismiss_panel(app: tauri::AppHandle, state: tauri::State<'_, Arc<AppState>>) {
    {
        let _latest = state.latest.lock().unwrap();
        let invocation = state.generation.fetch_add(1, Ordering::SeqCst) + 1;
        unsafe { splainit_set_invocation(invocation) };
    }
    let value = state.request_generation.fetch_add(1, Ordering::SeqCst) + 1;
    state.cancel_tx.send_replace(value);
    let ui_app = app.clone();
    let _ = app.run_on_main_thread(move || {
        if let Some(window) = ui_app.get_webview_window("main") {
            let _ = window.hide();
        }
    });
}

#[tauri::command]
async fn set_shortcut(app: tauri::AppHandle, state: tauri::State<'_, Arc<AppState>>, value: String) -> Result<String, String> {
    let state = state.inner().clone();
    tauri::async_runtime::spawn_blocking(move || set_shortcut_blocking(app, state, value))
        .await.map_err(|_| "Shortcut registration stopped unexpectedly".to_string())?
}

fn set_shortcut_blocking(app: tauri::AppHandle, state: Arc<AppState>, value: String) -> Result<String, String> {
    if value.len() > 64 {
        return Err("Shortcut is too long".into());
    }
    let requested = Shortcut::from_str(&value).map_err(|_| "Enter a shortcut such as Ctrl+Alt+K".to_string())?;
    if requested.mods.is_empty() || requested.mods == Modifiers::SHIFT {
        return Err("Use Control, Option, or Command with the key".into());
    }
    let mut active = state.shortcut.lock().unwrap();
    if active.0 == requested && active.1 {
        return Ok(format!("{} is ready", requested));
    }
    app.global_shortcut().register(requested)
        .map_err(|error| format!("Shortcut unavailable: {error}"))?;
    if active.1 {
        if let Err(error) = app.global_shortcut().unregister(active.0) {
            let _ = app.global_shortcut().unregister(requested);
            return Err(format!("Could not release old shortcut: {error}"));
        }
    }
    *active = (requested, true);
    let canonical = requested.to_string();
    let stored = CString::new(canonical.clone()).map_err(|_| "Invalid shortcut".to_string())?;
    unsafe { splainit_save_shortcut(stored.as_ptr()) };
    let status = format!("{} is ready", canonical);
    *state.shortcut_status.lock().unwrap() = status.clone();
    Ok(status)
}

pub fn run() {
    let stored = unsafe { splainit_load_shortcut() };
    let stored_value = if stored.is_null() {
        "Ctrl+Alt+K".to_string()
    } else {
        let value = unsafe { CStr::from_ptr(stored).to_string_lossy().into_owned() };
        unsafe { splainit_free(stored) };
        value
    };
    let shortcut = Shortcut::from_str(&stored_value).unwrap_or_else(|_| Shortcut::new(Some(Modifiers::CONTROL | Modifiers::ALT), Code::KeyK));
    let (cancel_tx, _) = watch::channel(0);
    let state = Arc::new(AppState {
        generation: AtomicU64::new(0),
        request_generation: AtomicU64::new(0),
        cancel_tx,
        latest: Mutex::new(None),
        shortcut_status: Mutex::new("Shortcut not registered".into()),
        shortcut: Mutex::new((shortcut, false)),
    });
    let handler_state = state.clone();
    let setup_state = state.clone();
    tauri::Builder::default()
        .manage(state)
        .manage(UpdateState::default())
        .plugin(tauri_plugin_updater::Builder::new().build())
        .plugin(
            tauri_plugin_global_shortcut::Builder::new()
                .with_handler(move |app, pressed, event| {
                    let is_current = handler_state.shortcut.lock().unwrap().0 == *pressed;
                    if is_current && event.state() == ShortcutState::Pressed {
                        begin_capture(app.clone(), handler_state.clone());
                    }
                })
                .build(),
        )
        .invoke_handler(tauri::generate_handler![latest_capture, drag_capture, shortcut_status, current_shortcut, set_shortcut, get_excluded_apps, set_excluded_apps, api_key_configured, save_api_key, remove_api_key, context_enabled, set_context_enabled, get_presets, explain_capture, cancel_explanation, dismiss_panel, get_model, set_model, history_enabled, set_history_enabled, list_history, delete_history_entry, clear_history, recover_capture_permission, accessibility_granted, request_accessibility, show_settings, hide_current_window, check_for_updates, install_update])
        .setup(move |app| {
            history::init(app.handle()).map_err(std::io::Error::other)?;
            let message = match app.global_shortcut().register(shortcut) {
                Ok(()) => {
                    setup_state.shortcut.lock().unwrap().1 = true;
                    format!("{} is ready", shortcut)
                }
                Err(error) => format!("{} is unavailable: {error}", shortcut),
            };
            *setup_state.shortcut_status.lock().unwrap() = message.clone();
            if !unsafe { splainit_accessibility_granted() } || !unsafe { splainit_has_api_key() } {
                if let Some(window) = app.get_webview_window("settings") {
                    window.show()?;
                }
            }
            if message.contains("unavailable") {
                if let Some(window) = app.get_webview_window("main") {
                    window.show()?;
                }
            }
            Ok(())
        })
        .run(tauri::generate_context!())
        .expect("failed to run Splainit");
}

// Explicit developer tooling only: no IPC, Keychain, preferences, or history.
#[cfg(feature = "live-provider-smoke")]
pub async fn live_provider_smoke(key: String) -> Result<String, String> {
    let model = openai::default_model();
    let prompt = prompts::compose(prompts::PresetId::ExplainSimply,
        "A triangle is a shape with three straight sides.", "", "")?;
    let (_cancel_tx, cancelled) = watch::channel(0);
    let started = std::time::Instant::now();
    let response = openai::explain(key, model, &prompt, cancelled).await
        .map_err(|error| format!("Live smoke FAILED; model={model}: {error}"))?;
    Ok(format!("Live transport PASS; model={model}; elapsed_ms={}\nReview this fixture reply before recording model acceptance:\n{}",
        started.elapsed().as_millis(), response))
}
