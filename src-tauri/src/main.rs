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

fn main() {
    tauri::Builder::default()
        .manage(Pending::default())
        .invoke_handler(tauri::generate_handler![resize, decide, menu_bar_height])
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
            thread::spawn(move || serve(handle));
            Ok(())
        })
        .run(tauri::generate_context!())
        .expect("error while running peep");
}
