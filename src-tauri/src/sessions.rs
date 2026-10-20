use std::process::Command;
use crate::macos::app_bundle_id;

fn parent_of(pid: i32) -> Option<i32> {
    let output = Command::new("ps").args(["-o", "ppid=", "-p", &pid.to_string()]).output().ok()?;
    String::from_utf8_lossy(&output.stdout).trim().parse().ok()
}

#[tauri::command]
pub fn session_app(pid: i32) -> Option<String> {
    let mut current = pid;
    while current > 1 {
        if let Some(bundle_id) = app_bundle_id(current) {
            return Some(bundle_id);
        }
        current = parent_of(current)?;
    }
    None
}

#[tauri::command]
pub fn open_session(pid: i32) -> Result<(), String> {
    let bundle_id = session_app(pid).ok_or("no app found")?;
    Command::new("open").args(["-b", &bundle_id]).status().map_err(|error| error.to_string())?;
    Ok(())
}

fn line_of(path: &str, needles: &[String]) -> usize {
    let text = std::fs::read_to_string(path).unwrap_or_default();
    needles.iter().filter(|needle| !needle.is_empty())
        .find_map(|needle| text.find(needle.as_str()))
        .map_or(1, |index| text[..index].matches('\n').count() + 1)
}

fn encode(path: &str) -> String {
    path.bytes().map(|byte| match byte {
        b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'/' | b'-' | b'_' | b'.' | b'~' => (byte as char).to_string(),
        _ => format!("%{byte:02X}"),
    }).collect()
}

#[tauri::command]
pub fn open_in_vscode(path: String, needles: Vec<String>) -> Result<(), String> {
    if !std::path::Path::new(&path).is_absolute() {
        return Err("not an absolute path".into());
    }
    let url = format!("vscode://file{}:{}", encode(&path), line_of(&path, &needles));
    Command::new("open").arg(url).status().map_err(|error| error.to_string())?;
    Ok(())
}

#[tauri::command]
pub fn read_file(path: String) -> Option<String> {
    let path = std::path::Path::new(&path);
    if !path.is_absolute() || std::fs::metadata(path).ok()?.len() > 1_000_000 {
        return None;
    }
    std::fs::read_to_string(path).ok()
}

fn is_transcript(path: &std::path::Path) -> bool {
    let projects = std::path::PathBuf::from(std::env::var("HOME").unwrap_or_default()).join(".claude/projects");
    path.is_absolute() && path.starts_with(projects) && path.extension().is_some_and(|extension| extension == "jsonl")
}

#[tauri::command]
pub fn context_used(path: String) -> Option<u64> {
    use std::io::{Read, Seek, SeekFrom};
    let path = std::path::Path::new(&path);
    if !is_transcript(path) {
        return None;
    }
    let mut file = std::fs::File::open(path).ok()?;
    let length = file.metadata().ok()?.len();
    file.seek(SeekFrom::Start(length.saturating_sub(512 * 1024))).ok()?;
    let mut bytes = Vec::new();
    file.read_to_end(&mut bytes).ok()?;
    String::from_utf8_lossy(&bytes).lines().rev().find_map(|line| {
        let entry: serde_json::Value = serde_json::from_str(line).ok()?;
        if entry["type"] != "assistant" || entry["isSidechain"] == true {
            return None;
        }
        let usage = entry["message"].get("usage")?;
        Some(["input_tokens", "cache_creation_input_tokens", "cache_read_input_tokens"].iter().filter_map(|key| usage[key].as_u64()).sum())
    })
}
