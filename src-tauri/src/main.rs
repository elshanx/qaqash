use std::collections::HashMap;
use std::sync::mpsc::{channel, Sender};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Mutex;
use std::process::Command;
use std::thread;
use std::time::Duration;
use serde_json::{json, Value};
use tauri::{ActivationPolicy, AppHandle, Emitter, LogicalPosition, LogicalSize, Manager, State, WebviewWindow};

#[derive(Default)]
struct Pending {
    next_id: AtomicU64,
    waiting: Mutex<HashMap<u64, Sender<Value>>>,
}

fn place(window: &WebviewWindow, width: f64, height: f64) -> tauri::Result<()> {
    let monitor = window.primary_monitor()?.unwrap();
    let screen_width = monitor.size().width as f64 / monitor.scale_factor();
    window.set_size(LogicalSize::new(width, height))?;
    window.set_position(LogicalPosition::new((screen_width - width) / 2.0, 0.0))
}

#[tauri::command]
fn menu_bar_height(window: WebviewWindow) -> Result<f64, String> {
    let monitor = window.primary_monitor().map_err(|e| e.to_string())?.ok_or("no monitor")?;
    Ok(monitor.work_area().position.y as f64 / monitor.scale_factor())
}

#[tauri::command]
fn resize(window: WebviewWindow, width: f64, height: f64) -> Result<(), String> {
    place(&window, width, height).map_err(|e| e.to_string())
}

#[tauri::command]
fn decide(pending: State<Pending>, id: u64, answer: Value) {
    if let Some(sender) = pending.waiting.lock().unwrap().remove(&id) {
        let _ = sender.send(answer);
    }
}

#[tauri::command]
fn forget(pending: State<Pending>, id: u64) {
    pending.waiting.lock().unwrap().remove(&id);
}

fn wait_for_user(app: &AppHandle, kind: &str, event: Value, timeout: Duration) -> Option<Value> {
    let pending = app.state::<Pending>();
    let id = pending.next_id.fetch_add(1, Ordering::Relaxed);
    let (sender, receiver) = channel();
    pending.waiting.lock().unwrap().insert(id, sender);
    play("Ping");
    let _ = app.emit("ask", json!({ "id": id, "kind": kind, "event": event }));

    let answer = receiver.recv_timeout(timeout).ok();
    pending.waiting.lock().unwrap().remove(&id);
    if answer.is_none() {
        let _ = app.emit("expired", id);
    }
    answer
}

fn answer_permission(app: &AppHandle, event: Value) -> String {
    let behavior = match wait_for_user(app, "permission", event, Duration::from_secs(580)) {
        Some(Value::Bool(true)) => json!({ "behavior": "allow" }),
        Some(_) => json!({ "behavior": "deny", "message": "Denied from Peep" }),
        None => return String::new(),
    };
    json!({ "hookSpecificOutput": { "hookEventName": "PermissionRequest", "decision": behavior } }).to_string()
}

fn answer_question(app: &AppHandle, event: Value) -> String {
    let mut input = event["tool_input"].clone();
    let Some(answers) = wait_for_user(app, "question", event, Duration::from_secs(30)) else {
        return String::new();
    };
    input["answers"] = answers;
    json!({ "hookSpecificOutput": { "hookEventName": "PreToolUse", "permissionDecision": "allow", "updatedInput": input } }).to_string()
}

fn claude_app_is_frontmost() -> bool {
    objc2::rc::autoreleasepool(|_| unsafe {
        let Some(workspace_class) = objc2::runtime::AnyClass::get(c"NSWorkspace") else { return false };
        let workspace: *mut objc2::runtime::AnyObject = objc2::msg_send![workspace_class, sharedWorkspace];
        let app: *mut objc2::runtime::AnyObject = objc2::msg_send![&*workspace, frontmostApplication];
        if app.is_null() {
            return false;
        }
        let bundle_id: *mut objc2::runtime::AnyObject = objc2::msg_send![&*app, bundleIdentifier];
        if bundle_id.is_null() {
            return false;
        }
        let utf8: *const std::ffi::c_char = objc2::msg_send![&*bundle_id, UTF8String];
        std::ffi::CStr::from_ptr(utf8).to_bytes() == b"com.anthropic.claudefordesktop"
    })
}

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

fn osascript(script: &str, args: &[&str]) -> Option<String> {
    let output = Command::new("osascript").arg("-e").arg(script).args(args).output().ok()?;
    output.status.success().then(|| String::from_utf8_lossy(&output.stdout).trim().to_string())
}

fn seconds(text: &str) -> f64 {
    text.replace(',', ".").parse().unwrap_or(0.0)
}

fn app_is_running(bundle_id: &std::ffi::CStr) -> bool {
    objc2::rc::autoreleasepool(|_| unsafe {
        let Some(app_class) = objc2::runtime::AnyClass::get(c"NSRunningApplication") else { return false };
        let Some(string_class) = objc2::runtime::AnyClass::get(c"NSString") else { return false };
        let id: *mut objc2::runtime::AnyObject = objc2::msg_send![string_class, stringWithUTF8String: bundle_id.as_ptr()];
        let apps: *mut objc2::runtime::AnyObject = objc2::msg_send![app_class, runningApplicationsWithBundleIdentifier: id];
        let count: usize = objc2::msg_send![&*apps, count];
        count > 0
    })
}

struct AppleScript(*mut objc2::runtime::AnyObject);

impl AppleScript {
    fn new(source: &str) -> Option<Self> {
        let source = std::ffi::CString::new(source).ok()?;
        unsafe {
            let string_class = objc2::runtime::AnyClass::get(c"NSString")?;
            let script_class = objc2::runtime::AnyClass::get(c"NSAppleScript")?;
            let text: *mut objc2::runtime::AnyObject = objc2::msg_send![string_class, stringWithUTF8String: source.as_ptr()];
            let script: *mut objc2::runtime::AnyObject = objc2::msg_send![script_class, alloc];
            let script: *mut objc2::runtime::AnyObject = objc2::msg_send![script, initWithSource: text];
            (!script.is_null()).then_some(Self(script))
        }
    }

    fn run(&self) -> Option<String> {
        objc2::rc::autoreleasepool(|_| unsafe {
            let mut error: *mut objc2::runtime::AnyObject = std::ptr::null_mut();
            let result: *mut objc2::runtime::AnyObject = objc2::msg_send![&*self.0, executeAndReturnError: &mut error];
            if result.is_null() {
                return None;
            }
            let text: *mut objc2::runtime::AnyObject = objc2::msg_send![&*result, stringValue];
            if text.is_null() {
                return Some(String::new());
            }
            let utf8: *const std::ffi::c_char = objc2::msg_send![&*text, UTF8String];
            Some(std::ffi::CStr::from_ptr(utf8).to_string_lossy().into_owned())
        })
    }
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

fn watch_music(app: AppHandle) {
    let (Some(spotify_script), Some(music_script)) = (AppleScript::new(SPOTIFY_NOW_PLAYING), AppleScript::new(MUSIC_NOW_PLAYING)) else {
        return;
    };
    loop {
        let _ = app.emit("music", now_playing(&spotify_script, &music_script));
        thread::sleep(Duration::from_secs(2));
    }
}

#[tauri::command]
fn music_artwork() -> Option<Vec<u8>> {
    if !app_is_running(c"com.apple.Music") {
        return None;
    }
    let path = std::env::temp_dir().join("peep-artwork");
    osascript(MUSIC_ARTWORK, &[path.to_str()?])?;
    std::fs::read(path).ok()
}

#[tauri::command]
fn music_control(player: String, action: String) -> Result<(), String> {
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

fn play(sound: &str) {
    let _ = Command::new("afplay").arg(format!("/System/Library/Sounds/{sound}.aiff")).spawn();
}

fn serve(app: AppHandle) {
    let server = tiny_http::Server::http("127.0.0.1:47831").expect("port 47831 in use");
    for mut request in server.incoming_requests() {
        let app = app.clone();
        thread::spawn(move || {
            let mut body = String::new();
            let _ = request.as_reader().read_to_string(&mut body);
            let event: Value = serde_json::from_str(&body).unwrap_or(Value::Null);
            let in_claude_app = claude_app_is_frontmost();
            let is_permission = event["hook_event_name"] == "PermissionRequest";
            let is_question = event["hook_event_name"] == "PreToolUse" && event["tool_name"] == "AskUserQuestion";
            let reply = if is_permission && !in_claude_app {
                answer_permission(&app, event)
            } else if is_question && !in_claude_app {
                answer_question(&app, event)
            } else {
                if event["hook_event_name"] == "Stop" && !in_claude_app {
                    play("Glass");
                }
                let _ = app.emit("status", event);
                String::new()
            };
            let _ = request.respond(tiny_http::Response::from_string(reply));
        });
    }
}

fn watch_hover(app: AppHandle, window: WebviewWindow) {
    let mut was_inside = false;
    loop {
        thread::sleep(Duration::from_millis(80));
        let (Ok(cursor), Ok(origin), Ok(size)) = (app.cursor_position(), window.outer_position(), window.outer_size()) else {
            continue;
        };
        let inside = cursor.x >= origin.x as f64
            && cursor.x < (origin.x + size.width as i32) as f64
            && cursor.y >= origin.y as f64
            && cursor.y < (origin.y + size.height as i32) as f64;
        if inside != was_inside {
            was_inside = inside;
            let _ = app.emit("hover", inside);
        }
    }
}

fn main() {
    tauri::Builder::default()
        .manage(Pending::default())
        .invoke_handler(tauri::generate_handler![resize, decide, forget, menu_bar_height, music_control, music_artwork])
        .setup(|app| {
            app.set_activation_policy(ActivationPolicy::Accessory);

            let window = app.get_webview_window("main").unwrap();
            place(&window, 370.0, 38.0)?;

            let ns_window = window.ns_window()? as *const objc2::runtime::AnyObject;
            unsafe {
                let _: () = objc2::msg_send![&*ns_window, setLevel: 25isize];
                let _: () = objc2::msg_send![&*ns_window, setAcceptsMouseMovedEvents: true];
            }

            window.show()?;

            let handle = app.handle().clone();
            let music_handle = handle.clone();
            let hover_handle = handle.clone();
            thread::spawn(move || serve(handle));
            thread::spawn(move || watch_music(music_handle));
            thread::spawn(move || watch_hover(hover_handle, window));
            Ok(())
        })
        .run(tauri::generate_context!())
        .expect("error while running peep");
}
