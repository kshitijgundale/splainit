fn main() {
    println!("cargo:rerun-if-changed=src/macos/selection.m");
    println!("cargo:rerun-if-changed=src/macos/resolver.m");
    println!("cargo:rerun-if-changed=src/macos/resolver.h");
    println!("cargo:rerun-if-changed=src/macos/visual.h");
    println!("cargo:rerun-if-changed=src/macos/visual.m");
    println!("cargo:rerun-if-changed=default-model.txt");
    let model = format!("\"{}\"", include_str!("default-model.txt").trim());
    cc::Build::new()
        .define("SPLAINIT_DEFAULT_MODEL", model.as_str())
        .file("src/macos/selection.m")
        .file("src/macos/resolver.m")
        .file("src/macos/visual.m")
        .flag("-fobjc-arc")
        .flag("-mmacosx-version-min=14.0")
        .compile("splainit_selection");
    println!("cargo:rustc-link-lib=framework=AppKit");
    println!("cargo:rustc-link-lib=framework=ApplicationServices");
    println!("cargo:rustc-link-lib=framework=Security");
    println!("cargo:rustc-link-lib=framework=Vision");
    tauri_build::try_build(
        tauri_build::Attributes::new().app_manifest(
            tauri_build::AppManifest::new().commands(&[
                "latest_capture", "drag_capture", "shortcut_status", "current_shortcut", "set_shortcut",
                "get_excluded_apps", "set_excluded_apps", "api_key_configured",
                "save_api_key", "remove_api_key", "context_enabled", "set_context_enabled",
                "get_presets", "explain_capture", "cancel_explanation", "dismiss_panel",
                "get_model", "set_model", "history_enabled", "set_history_enabled",
                "list_history", "delete_history_entry", "clear_history",
                "recover_capture_permission", "accessibility_granted", "request_accessibility", "show_settings",
                "hide_current_window",
                "check_for_updates", "install_update",
            ]),
        ),
    ).expect("failed to build Tauri app");
}
