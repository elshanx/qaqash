use std::collections::{BTreeMap, VecDeque};
use std::path::PathBuf;
use std::process::Command;
use std::sync::{Condvar, Mutex, OnceLock};
use std::thread;
use std::time::Duration;
use serde_json::{json, Value};
use sha2::{Digest, Sha256};
use tauri::{AppHandle, Manager};
use crate::hooks::{resolve, Pending};

const PORT: u16 = 47832;
const ANSWER_PORT: u16 = 47833;
const LONG_POLL: Duration = Duration::from_secs(25);
const NUDGE_AFTER: Duration = Duration::from_secs(10);
const KEPT_EVENTS: usize = 200;

struct Feed {
    seq: u64,
    events: VecDeque<Value>,
    asks: BTreeMap<u64, Value>,
    sessions: BTreeMap<String, Value>,
}

static FEED: Mutex<Feed> = Mutex::new(Feed { seq: 0, events: VecDeque::new(), asks: BTreeMap::new(), sessions: BTreeMap::new() });
static CHANGED: Condvar = Condvar::new();
static SETTINGS: OnceLock<Mutex<Settings>> = OnceLock::new();
static ANSWER_KEYS: Mutex<BTreeMap<String, u64>> = Mutex::new(BTreeMap::new());

#[derive(Clone)]
struct Settings {
    path: PathBuf,
    token: String,
    certificate: String,
    private_key: String,
    pin: String,
    ntfy_topic: String,
}

fn random_hex(size: usize) -> Option<String> {
    let mut bytes = vec![0u8; size];
    getrandom::fill(&mut bytes).ok()?;
    Some(hex(&bytes))
}

fn hex(bytes: &[u8]) -> String {
    bytes.iter().map(|byte| format!("{byte:02x}")).collect()
}

fn local_host_name() -> String {
    let output = Command::new("scutil").args(["--get", "LocalHostName"]).output();
    output.map(|output| String::from_utf8_lossy(&output.stdout).trim().to_string()).unwrap_or_default()
}

fn wifi_address() -> String {
    let output = Command::new("ipconfig").args(["getifaddr", "en0"]).output();
    output.map(|output| String::from_utf8_lossy(&output.stdout).trim().to_string()).unwrap_or_default()
}

fn create_settings(path: PathBuf) -> Option<Settings> {
    let names = vec![format!("{}.local", local_host_name()), "qaqash.local".into()];
    let certified = rcgen::generate_simple_self_signed(names).ok()?;
    let settings = Settings {
        path,
        token: random_hex(32)?,
        certificate: certified.cert.pem(),
        private_key: certified.signing_key.serialize_pem(),
        pin: hex(&Sha256::digest(certified.cert.der())),
        ntfy_topic: String::new(),
    };
    save(&settings);
    Some(settings)
}

fn load_settings(path: PathBuf) -> Option<Settings> {
    let saved: Value = serde_json::from_str(&std::fs::read_to_string(&path).ok()?).ok()?;
    let text = |key: &str| saved[key].as_str().map(str::to_string);
    Some(Settings {
        path,
        token: text("token")?,
        certificate: text("certificate")?,
        private_key: text("private_key")?,
        pin: text("pin")?,
        ntfy_topic: text("ntfy_topic").unwrap_or_default(),
    })
}

fn save(settings: &Settings) {
    use std::os::unix::fs::OpenOptionsExt;
    let saved = json!({
        "token": settings.token,
        "certificate": settings.certificate,
        "private_key": settings.private_key,
        "pin": settings.pin,
        "ntfy_topic": settings.ntfy_topic,
    });
    if let Some(folder) = settings.path.parent() {
        let _ = std::fs::create_dir_all(folder);
    }
    let file = std::fs::OpenOptions::new().write(true).create(true).truncate(true).mode(0o600).open(&settings.path);
    if let Ok(mut file) = file {
        let _ = std::io::Write::write_all(&mut file, saved.to_string().as_bytes());
    }
}

fn settings() -> Option<Settings> {
    SETTINGS.get().map(|settings| settings.lock().unwrap().clone())
}

fn publish(feed: &mut Feed, kind: &str, data: Value) {
    feed.seq += 1;
    feed.events.push_back(json!({ "seq": feed.seq, "kind": kind, "data": data }));
    if feed.events.len() > KEPT_EVENTS {
        feed.events.pop_front();
    }
    CHANGED.notify_all();
}

pub fn ask_opened(ask: &Value) {
    let Some(id) = ask["id"].as_u64() else { return };
    let mut feed = FEED.lock().unwrap();
    feed.asks.insert(id, ask.clone());
    publish(&mut feed, "ask", ask.clone());
    drop(feed);
    let ask = ask.clone();
    thread::spawn(move || {
        thread::sleep(NUDGE_AFTER);
        if FEED.lock().unwrap().asks.contains_key(&id) {
            nudge(&ask);
        }
    });
}

pub fn ask_closed(id: u64) {
    let mut feed = FEED.lock().unwrap();
    ANSWER_KEYS.lock().unwrap().retain(|_, ask| *ask != id);
    if feed.asks.remove(&id).is_some() {
        publish(&mut feed, "resolved", json!({ "id": id }));
    }
}

pub fn status(event: &Value) {
    let mut feed = FEED.lock().unwrap();
    if let (Some(session), true) = (event["session_id"].as_str(), event["transcript_path"].is_string()) {
        if event["hook_event_name"] == "SessionEnd" {
            feed.sessions.remove(session);
        } else {
            feed.sessions.insert(session.to_string(), event.clone());
        }
    }
    publish(&mut feed, "status", event.clone());
}

fn nudge(ask: &Value) {
    let Some(topic) = settings().map(|settings| settings.ntfy_topic).filter(|topic| !topic.is_empty()) else { return };
    let project = ask["event"]["cwd"].as_str().and_then(|cwd| cwd.rsplit('/').next()).unwrap_or("Claude");
    let mut message = json!({ "topic": topic, "title": project, "priority": 4, "tags": ["eyes"] });
    if ask["kind"] == "question" {
        message["message"] = "Claude has a question for you.".into();
    } else {
        message["message"] = format!("Claude wants to use {}.", ask["event"]["tool_name"].as_str().unwrap_or("a tool")).into();
        if let (Some(id), Some(key)) = (ask["id"].as_u64(), random_hex(16)) {
            ANSWER_KEYS.lock().unwrap().insert(key.clone(), id);
            let url = format!("http://{}:{ANSWER_PORT}/answer", wifi_address());
            let button = |label: &str, body: &str| json!({ "action": "http", "label": label, "url": url, "headers": { "X-Answer-Key": key }, "body": body, "clear": true });
            message["actions"] = json!([button("Deny", "deny"), button("Allow", "allow")]);
        }
    }
    let _ = Command::new("curl").args(["-s", "-m", "10", "-H", "Content-Type: application/json", "-d", &message.to_string(), "https://ntfy.sh"]).output();
}

fn answer_from_notification(app: &AppHandle, mut request: tiny_http::Request) {
    let key = request.headers().iter().find(|header| header.field.equiv("X-Answer-Key")).map(|header| header.value.to_string());
    let id = key.and_then(|key| ANSWER_KEYS.lock().unwrap().remove(&key));
    let mut body = String::new();
    let _ = request.as_reader().read_to_string(&mut body);
    match id {
        Some(id) if request.url() == "/answer" => {
            resolve(&app.state::<Pending>(), id, Value::Bool(body.trim() == "allow"));
            reply(request, 200, json!({ "ok": true }))
        }
        _ => reply(request, 403, json!({ "error": "unknown or used key" })),
    }
}

pub fn serve_answers(app: AppHandle) {
    let Ok(server) = tiny_http::Server::http(("0.0.0.0", ANSWER_PORT)) else { return };
    for request in server.incoming_requests() {
        let app = app.clone();
        thread::spawn(move || answer_from_notification(&app, request));
    }
}

fn snapshot() -> Value {
    let feed = FEED.lock().unwrap();
    json!({
        "seq": feed.seq,
        "asks": feed.asks.values().collect::<Vec<_>>(),
        "sessions": feed.sessions.values().collect::<Vec<_>>(),
    })
}

fn events_after(after: u64) -> Value {
    let mut feed = FEED.lock().unwrap();
    if feed.seq <= after {
        feed = CHANGED.wait_timeout_while(feed, LONG_POLL, |feed| feed.seq <= after).unwrap().0;
    }
    let oldest = feed.events.front().and_then(|event| event["seq"].as_u64()).unwrap_or(feed.seq + 1);
    if after + 1 < oldest && after < feed.seq {
        return json!({ "seq": feed.seq, "reset": true, "events": [] });
    }
    let events: Vec<&Value> = feed.events.iter().filter(|event| event["seq"].as_u64() > Some(after)).collect();
    json!({ "seq": feed.seq, "events": events })
}

fn authorized(request: &tiny_http::Request, token: &str) -> bool {
    let expected = format!("Bearer {token}");
    request.headers().iter().any(|header| {
        header.field.equiv("Authorization") && {
            let given = header.value.as_str().as_bytes();
            given.len() == expected.len() && given.iter().zip(expected.as_bytes()).fold(0, |diff, (a, b)| diff | (a ^ b)) == 0
        }
    })
}

fn reply(request: tiny_http::Request, code: u16, body: Value) {
    let header = tiny_http::Header::from_bytes("Content-Type", "application/json").unwrap();
    let _ = request.respond(tiny_http::Response::from_string(body.to_string()).with_status_code(code).with_header(header));
}

fn handle(app: &AppHandle, mut request: tiny_http::Request, token: &str) {
    if !authorized(&request, token) {
        return reply(request, 401, json!({ "error": "not paired" }));
    }
    let url = request.url().to_string();
    let (path, query) = url.split_once('?').unwrap_or((&url, ""));
    match (request.method(), path) {
        (tiny_http::Method::Get, "/state") => reply(request, 200, snapshot()),
        (tiny_http::Method::Get, "/events") => {
            let after = query.strip_prefix("after=").and_then(|after| after.parse().ok()).unwrap_or(0);
            reply(request, 200, events_after(after))
        }
        (tiny_http::Method::Post, "/decide") => {
            let mut body = String::new();
            let _ = request.as_reader().read_to_string(&mut body);
            let decision: Value = serde_json::from_str(&body).unwrap_or(Value::Null);
            match decision["id"].as_u64() {
                Some(id) => {
                    resolve(&app.state::<Pending>(), id, decision["answer"].clone());
                    reply(request, 200, json!({ "ok": true }))
                }
                None => reply(request, 400, json!({ "error": "missing id" })),
            }
        }
        _ => reply(request, 404, json!({ "error": "not found" })),
    }
}

pub fn serve(app: AppHandle) {
    let Ok(folder) = app.path().app_config_dir() else { return };
    let path = folder.join("phone.json");
    let Some(settings) = load_settings(path.clone()).or_else(|| create_settings(path)) else { return };
    let config = tiny_http::SslConfig {
        certificate: settings.certificate.clone().into_bytes(),
        private_key: settings.private_key.clone().into_bytes(),
    };
    let token = settings.token.clone();
    let _ = SETTINGS.set(Mutex::new(settings));
    let Ok(server) = tiny_http::Server::https(("0.0.0.0", PORT), config) else { return };
    for request in server.incoming_requests() {
        let app = app.clone();
        let token = token.clone();
        thread::spawn(move || handle(&app, request, &token));
    }
}

fn pairing() -> Result<Value, String> {
    let settings = settings().ok_or("phone link is not ready")?;
    let name = local_host_name();
    Ok(json!({
        "v": 1,
        "host": format!("{name}.local"),
        "name": name,
        "ip": wifi_address(),
        "port": PORT,
        "token": settings.token,
        "pin": settings.pin,
    }))
}

#[tauri::command]
pub fn pairing_code() -> Result<String, String> {
    let code = qrcode::QrCode::new(pairing()?.to_string()).map_err(|error| error.to_string())?;
    Ok(code.render::<qrcode::render::svg::Color>().min_dimensions(220, 220).quiet_zone(false).build())
}

#[tauri::command]
pub fn pairing_text() -> Result<String, String> {
    Ok(pairing()?.to_string())
}

#[tauri::command]
pub fn ntfy_topic() -> String {
    settings().map(|settings| settings.ntfy_topic).unwrap_or_default()
}

#[tauri::command]
pub fn set_notifications(on: bool) -> String {
    let Some(settings) = SETTINGS.get() else { return String::new() };
    let mut settings = settings.lock().unwrap();
    settings.ntfy_topic = if on { random_hex(10).map(|id| format!("qaqash-{id}")).unwrap_or_default() } else { String::new() };
    save(&settings);
    settings.ntfy_topic.clone()
}
