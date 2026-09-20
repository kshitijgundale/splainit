use serde::Serialize;
use std::time::Duration;
use tauri_plugin_updater::{Update, UpdaterExt};
use tokio::sync::Mutex;

#[derive(Default)]
pub struct UpdateState(Mutex<Option<Update>>);

#[derive(Serialize)]
pub struct AvailableUpdate {
    version: String,
}

#[tauri::command]
pub async fn check_for_updates(
    app: tauri::AppHandle,
    state: tauri::State<'_, UpdateState>,
) -> Result<Option<AvailableUpdate>, String> {
    let mut pending = state.0.try_lock().map_err(|_| "An update operation is already running")?;
    *pending = None;
    let updater = app.updater_builder().timeout(Duration::from_secs(120)).build()
        .map_err(|_| "Updates are not configured in this build")?;
    let update = updater.check().await
        .map_err(|_| "Could not check for updates. Check your connection and try again.")?;
    let summary = update.as_ref().map(|value| AvailableUpdate { version: value.version.clone() });
    *pending = update;
    Ok(summary)
}

#[tauri::command]
pub async fn install_update(
    app: tauri::AppHandle,
    state: tauri::State<'_, UpdateState>,
    version: String,
) -> Result<(), String> {
    let mut pending = state.0.try_lock().map_err(|_| "An update operation is already running")?;
    if pending.as_ref().map(|update| update.version.as_str()) != Some(version.as_str()) {
        return Err("Check for updates again before installing".into());
    }
    let update = pending.take().ok_or("Check for updates again before installing")?;
    // Tauri verifies the downloaded archive against the embedded public key
    // before replacing the installed app. No URL, key, or signature comes from IPC.
    update.download_and_install(|_, _| {}, || {}).await
        .map_err(|_| "Update could not be verified or installed. Check for updates and retry.")?;
    app.restart();
}
