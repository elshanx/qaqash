# Peep

A fully local, notch-style companion for Claude Code on macOS (MacBook Air M2, 8GB RAM). Own project, own name and character; not a fork of Coucou.

## Goal
A small black pill at the top-centre of the screen that looks like the notch growing. It shows what Claude Code is doing and lets the user Allow/Deny permission requests. No cloud, no model, no account. Everything is localhost.

## Stack
Tauri 2 (Rust backend) + Vite + vanilla TypeScript frontend. Chosen over Electron for low RAM on 8GB. The user is a frontend developer: keep the Rust small and explain it.

## Design
1. Claude Code hooks run `scripts/hook.sh`, which pipes the hook JSON from stdin to `http://127.0.0.1:47831/event` with curl and prints the response.
2. The Rust app runs a tiny HTTP server (tiny_http) on that port, in a background thread, one thread per request.
3. `PermissionRequest` events: emit a `permission` event to the frontend, block the request on an mpsc channel until the `decide(id, allow)` command is called, then answer with
   `{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}` (or `"deny"` with a `message`).
   On timeout (~580s) answer with an empty body so Claude falls back to its normal prompt.
4. Other events (UserPromptSubmit, PreToolUse, Notification, Stop) are emitted as `status` and answered immediately with an empty body.
5. Fail-safe: if the app is not running, curl fails and hook.sh exits 0 with no output, so Claude Code behaves normally.

## Window
- Frameless, transparent, always on top, no Dock icon (ActivationPolicy::Accessory), `macOSPrivateApi` true (Cargo feature `macos-private-api` must match), `acceptFirstMouse` true, visible on all workspaces.
- Position: top-centre of the primary monitor at y=0.
- macOS pushes windows below the menu bar. Raise the NSWindow level to 25 via the `objc2` crate (`msg_send![ns_window, setLevel: 25isize]`).
- Resize the window per state (collapsed about 370x38, expanded about 460x210) through a Rust `resize` command that also re-centres it. A big transparent window would block clicks on the menu bar.
- Notch width is not exposed to Electron/Tauri. Hard-code about 190pt as a CSS variable and tune by eye. The pill is full window width, black, with border-radius 0 0 20px 20px.

## Rules for working here
- Run and test locally (`npm install`, `npm run tauri dev`). Prefer verifying the notch look on screen over assuming.
- Do not edit `~/.claude/settings.json` without asking. Provide `claude-hooks.example.json` and let the user merge it.
- Keep it offline-only. No telemetry, no network calls beyond 127.0.0.1.
- Music (Spotify, Apple Music) is read and controlled with local AppleScript via `osascript`. Only query an app after `NSRunningApplication` confirms it is running, so Peep never launches a music app. No Spotify cover art (it would need a network fetch); Apple Music art is read locally.
- Stay quiet while the Claude desktop app (`com.anthropic.claudefordesktop`) is frontmost: no prompts, no sounds.

## Build order
1. Scaffold the project and get a transparent pill showing at the top centre.
2. Hook server + status text.
3. Allow/Deny round trip with a real Claude Code session.
4. Polish: animation, sound on Stop, multiple pending requests, stale request cleanup if the hook process dies.
5. Later, optional: local chat via Ollama, local dictation.
