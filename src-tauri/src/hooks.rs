use std::collections::HashMap;
use std::process::Command;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::mpsc::{channel, Sender};
use std::sync::Mutex;
use std::thread;
use std::time::Duration;
use serde_json::{json, Value};
use tauri::{AppHandle, Emitter, Manager, State};
use crate::macos::claude_app_is_frontmost;

#[derive(Default)]
pub struct Pending {
    next_id: AtomicU64,
    waiting: Mutex<HashMap<u64, Sender<Value>>>,
}

#[tauri::command]
pub fn decide(pending: State<Pending>, id: u64, answer: Value) {
    if let Some(sender) = pending.waiting.lock().unwrap().remove(&id) {
        let _ = sender.send(answer);
    }
}

#[tauri::command]
pub fn forget(pending: State<Pending>, id: u64) {
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

fn play(sound: &str) {
    let _ = Command::new("afplay").arg(format!("/System/Library/Sounds/{sound}.aiff")).spawn();
}

pub fn serve(app: AppHandle) {
    let server = tiny_http::Server::http("127.0.0.1:47831").expect("port 47831 in use");
    for mut request in server.incoming_requests() {
        let app = app.clone();
        thread::spawn(move || {
            let mut body = String::new();
            let _ = request.as_reader().read_to_string(&mut body);
            let mut event: Value = serde_json::from_str(&body).unwrap_or(Value::Null);
            let pid = request.headers().iter().find(|header| header.field.equiv("X-Peep-Pid")).and_then(|header| header.value.as_str().parse::<i32>().ok());
            if let (Some(pid), Some(fields)) = (pid, event.as_object_mut()) {
                fields.insert("peep_pid".into(), pid.into());
            }
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
