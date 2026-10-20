use std::thread;
use std::time::Duration;
use serde_json::{json, Value};
use tauri::{AppHandle, Emitter};
use crate::macos::{app_is_running, osascript, AppleScript};

const SPOTIFY_NOW_PLAYING: &str = r#"
tell application "Spotify"
    if player state is stopped then return ""
    return (player state as text) & tab & (name of current track) & tab & (artist of current track) & tab & (album of current track) & tab & (player position as text) & tab & ((duration of current track) / 1000 as text) & tab & (artwork url of current track)
end tell
"#;

const MUSIC_NOW_PLAYING: &str = r#"
tell application "Music"
    if player state is stopped then return ""
    set state to player state as text
    try
        return state & tab & (name of current track) & tab & (artist of current track) & tab & (album of current track) & tab & (player position as text) & tab & (duration of current track as text)
    end try
    return state & tab & "Apple Music Radio" & tab & "Live" & tab & "Radio" & tab & "0" & tab & "0"
end tell
"#;

const MUSIC_ARTWORK: &str = r#"
on run argv
    tell application "Music" to set artworkData to raw data of artwork 1 of current track
    set artworkFile to open for access (POSIX file (item 1 of argv)) with write permission
    set eof artworkFile to 0
    write artworkData to artworkFile
    close access artworkFile
end run
"#;

fn seconds(text: &str) -> f64 {
    text.replace(',', ".").parse().unwrap_or(0.0)
}

fn query_player(player: &str, bundle_id: &std::ffi::CStr, script: &AppleScript) -> Value {
    if !app_is_running(bundle_id) {
        return Value::Null;
    }
    let Some(line) = script.run() else { return Value::Null };
    let fields: Vec<&str> = line.split('\t').collect();
    if fields.len() < 6 {
        return Value::Null;
    }
    json!({
        "app": player,
        "playing": fields[0] == "playing",
        "title": fields[1],
        "artist": fields[2],
        "album": fields[3],
        "position": seconds(fields[4]),
        "duration": seconds(fields[5]),
        "artworkUrl": fields.get(6),
    })
}

fn now_playing(spotify_script: &AppleScript, music_script: &AppleScript) -> Value {
    let spotify = query_player("Spotify", c"com.spotify.client", spotify_script);
    if spotify["playing"] == true {
        return spotify;
    }
    let music = query_player("Music", c"com.apple.Music", music_script);
    if music.is_null() { spotify } else { music }
}

pub fn watch_music(app: AppHandle) {
    let (Some(spotify_script), Some(music_script)) = (AppleScript::new(SPOTIFY_NOW_PLAYING), AppleScript::new(MUSIC_NOW_PLAYING)) else {
        return;
    };
    loop {
        let _ = app.emit("music", now_playing(&spotify_script, &music_script));
        thread::sleep(Duration::from_secs(2));
    }
}

#[tauri::command]
pub fn music_artwork() -> Option<Vec<u8>> {
    if !app_is_running(c"com.apple.Music") {
        return None;
    }
    let path = std::env::temp_dir().join("qaqash-artwork");
    osascript(MUSIC_ARTWORK, &[path.to_str()?])?;
    std::fs::read(path).ok()
}

#[tauri::command]
pub fn music_control(player: String, action: String) -> Result<(), String> {
    let (player, bundle_id) = match player.as_str() {
        "Spotify" => ("Spotify", c"com.spotify.client"),
        "Music" => ("Music", c"com.apple.Music"),
        _ => return Err("unknown player".into()),
    };
    if !app_is_running(bundle_id) {
        return Err("music app is not running".into());
    }
    let commands = match (action.as_str(), player) {
        ("toggle", _) => "playpause",
        ("next", _) => "next track",
        ("previous", _) => "previous track",
        ("open", "Music") => "try\nreveal current track\nend try\nactivate",
        ("open", _) => "activate",
        _ => return Err("unknown action".into()),
    };
    osascript(&format!("tell application \"{player}\"\n{commands}\nend tell"), &[]).map(|_| ()).ok_or("music app did not respond".into())
}
