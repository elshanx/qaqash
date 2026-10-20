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
    waiting: Mutex<HashMap<u64, Sender<bool>>>,
}

fn place(window: &WebviewWindow, width: f64, height: f64) -> tauri::Result<()> {
    let monitor = window.primary_monitor()?.unwrap();
    let screen_width = monitor.size().width as f64 / monitor.scale_factor();
    let top = if cfg!(debug_assertions) { 40.0 } else { 0.0 };
    window.set_size(LogicalSize::new(width, height))?;
    window.set_position(LogicalPosition::new((screen_width - width) / 2.0, top))
}

#[tauri::command]
fn resize(window: WebviewWindow, width: f64, height: f64) -> Result<(), String> {
    place(&window, width, height).map_err(|e| e.to_string())
}

#[tauri::command]
fn decide(pending: State<Pending>, id: u64, allow: bool) {
    if let Some(sender) = pending.waiting.lock().unwrap().remove(&id) {
        let _ = sender.send(allow);
    }
}

fn answer_permission(app: &AppHandle, event: Value) -> String {
    let pending = app.state::<Pending>();
    let id = pending.next_id.fetch_add(1, Ordering::Relaxed);
    let (sender, receiver) = channel();
    pending.waiting.lock().unwrap().insert(id, sender);
    let _ = app.emit("permission", json!({ "id": id, "event": event }));

    let decision = receiver.recv_timeout(Duration::from_secs(580));
    pending.waiting.lock().unwrap().remove(&id);
    let behavior = match decision {
        Ok(true) => json!({ "behavior": "allow" }),
        Ok(false) => json!({ "behavior": "deny", "message": "Denied from Peep" }),
        Err(_) => return String::new(),
    };
    json!({ "hookSpecificOutput": { "hookEventName": "PermissionRequest", "decision": behavior } }).to_string()
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
            let reply = if event["hook_event_name"] == "PermissionRequest" {
                play("Ping");
                answer_permission(&app, event)
            } else {
                if event["hook_event_name"] == "Stop" {
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
        .invoke_handler(tauri::generate_handler![resize, decide])
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
