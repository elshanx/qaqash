use crate::macos::{app_is_running, osascript};

const FRONT_WINDOW: &str = r#"tell application "System Events" to tell process "Code" to get name of front window"#;

#[tauri::command]
pub fn vscode_window() -> Option<String> {
    if !app_is_running(c"com.microsoft.VSCode") {
        return None;
    }
    osascript(FRONT_WINDOW, &[])
}

#[tauri::command]
pub fn open_vscode() -> Result<(), String> {
    std::process::Command::new("open").args(["-b", "com.microsoft.VSCode"]).status().map_err(|error| error.to_string())?;
    Ok(())
}
