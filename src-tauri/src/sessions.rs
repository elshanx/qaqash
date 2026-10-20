use std::process::Command;
use crate::macos::app_bundle_id;

fn parent_of(pid: i32) -> Option<i32> {
    let output = Command::new("ps").args(["-o", "ppid=", "-p", &pid.to_string()]).output().ok()?;
    String::from_utf8_lossy(&output.stdout).trim().parse().ok()
}

#[tauri::command]
pub fn open_session(pid: i32) -> Result<(), String> {
    let mut current = pid;
    while current > 1 {
        if let Some(bundle_id) = app_bundle_id(current) {
            Command::new("open").args(["-b", &bundle_id]).status().map_err(|error| error.to_string())?;
            return Ok(());
        }
        current = parent_of(current).ok_or("process ended")?;
    }
    Err("no app found".into())
}
