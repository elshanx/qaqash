# Qaqash

A fully local, notch-style personal companion on macOS. It starts with Claude Code and music, and will grow to cover VS Code, Telegram, WhatsApp, Mail and terminal notifications (MacBook Air M2, 8GB RAM). Own project, own name and character; not a fork of Coucou.

## Goal
A small black island at the top-centre of the screen that looks like the notch growing. It shows what Claude Code is doing and lets the user Allow/Deny permission requests. No cloud, no model, no account. Everything is localhost.

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
- The window is a fixed transparent canvas (540x560) that ignores the mouse, so it never resizes mid-animation. Rust polls the cursor and only accepts clicks over the island area the frontend reports with `set_hit_area`. It also sends the cursor position, because the webview gets no hover events while another app is in front.
- Notch width is not exposed to Electron/Tauri. Hard-code about 190pt as a CSS variable and tune by eye. The island is black and centred in the canvas, with rounded bottom corners.

## Structure
One file per concern. Put new code in the file that owns it, or a new file for a new concern; keep `main.ts` and `main.rs` to wiring only.
- `src/`: `main.ts` (wiring), `island.ts` (sizing and `render`), `prompts.ts`, `sessions.ts`, `music.ts`, `hover.ts`, `mood.ts`, `motion.ts` (spring curves), `hook-events.ts` (event wording), `state.ts`, `dom.ts`, `types.ts`.
- `src/styles/`: `base`, `island`, `face`, `prompt`, `sessions`, `music`.
- `src-tauri/src/`: `main.rs` (wiring), `window.rs` (canvas, hit area, hover), `hooks.rs` (hook server, Allow/Deny), `music.rs`, `sessions.rs`, `macos.rs` (Objective-C and AppleScript helpers).

## Rules for working here
- Run and test locally (`npm install`, `npm run tauri dev`). Prefer verifying the notch look on screen over assuming.
- Do not edit `~/.claude/settings.json` without asking. Provide `claude-hooks.example.json` and let the user merge it.
- Keep it offline-only. No telemetry, no network calls beyond 127.0.0.1. One exception the user approved: Spotify cover images load from `https://i.scdn.co` (checked in the frontend before use).
- Music (Spotify, Apple Music) is read and controlled with local AppleScript via `osascript`. Only query an app after `NSRunningApplication` confirms it is running, so Qaqash never launches a music app. Apple Music art is read locally; Apple Music radio has no track info, so it shows as "Apple Music Radio".
- Stay quiet while the Claude desktop app (`com.anthropic.claudefordesktop`) is frontmost: no prompts, no sounds.

## Build order
1. Scaffold the project and get a transparent island showing at the top centre.
2. Hook server + status text.
3. Allow/Deny round trip with a real Claude Code session.
4. Polish: animation, sound on Stop, multiple pending requests, stale request cleanup if the hook process dies.
5. Later, optional: local chat via Ollama, local dictation.
