# Qaqash

A fully local, notch-style personal companion on macOS. It starts with Claude Code and music, and will grow to cover VS Code, Telegram, WhatsApp, Mail and terminal notifications (MacBook Air M2, 8GB RAM). Own project, own name and character (the mascot, the pair of eyes, is also called Qaqash); not a fork of Coucou.

## Goal
A small black island at the top-centre of the screen that looks like the notch growing. It shows what Claude Code is doing and lets the user Allow/Deny permission requests. No cloud, no model, no account. Everything is localhost.

## Stack
Native Swift + SwiftUI, macOS 15+, built as a Swift package with no dependencies (Network, CryptoKit, CoreImage, AppKit only). Rewritten from Tauri for lower RAM on 8GB and native animation. The user is a frontend developer: keep the Swift small and explain it.

## Design
1. Claude Code hooks run `scripts/hook.sh`, which pipes the hook JSON from stdin to `http://127.0.0.1:47831/event` with curl and prints the response.
2. The app runs a tiny HTTP server (`HTTP.swift`, on `NWListener`) on that port, loopback only, each request handled on a background queue.
3. `PermissionRequest` events: show the ask in the island, block the request on a semaphore until the user decides (`state.decide`), then answer with
   `{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}` (or `"deny"` with a `message`).
   On timeout (~580s) answer with an empty body so Claude falls back to its normal prompt.
4. Other events (UserPromptSubmit, PreToolUse, Notification, Stop) update the island state and are answered immediately with an empty body.
5. Fail-safe: if the app is not running, curl fails and hook.sh exits 0 with no output, so Claude Code behaves normally.

## Window
- A borderless, non-activating `NSPanel`, transparent, no Dock icon (`LSUIElement`, `.accessory`), first mouse accepted, visible on all Spaces.
- Position: top-centre of the primary screen at y=0, window level 25 so it sits over the menu bar (`constrainFrameRect` is overridden so macOS doesn't push it down).
- The window is a fixed transparent canvas (540x560) that ignores the mouse, so it never resizes mid-animation. A 30ms timer polls the cursor and only accepts clicks over the island's size (`state.hit`, reported by `onGeometryChange`).
- The notch is about 190pt wide; the status text starts just right of it. The island is black and centred in the canvas, with rounded bottom corners and inverse-rounded "ears".
- Animations use SwiftUI springs (`.morph` = response 0.45, damping 0.68). Never use `repeatForever` with `withAnimation`: views holding one never finish their removal transition. Use `keyframeAnimator(repeating:)` or `phaseAnimator`.

## Structure
One file per concern, each holding its state logic (as an `AppState` extension) and its views. Put new code in the file that owns it, or a new file for a new concern; keep `main.swift` to wiring only.
- `Sources/Qaqash/`: `main.swift` (wiring), `State.swift` (`AppState`, the one `@Observable` store, and `HookEvent`), `Window.swift` (panel, hit area, hover), `Island.swift` (island shape, bar, pages), `Face.swift` (eyes, avatar), `Style.swift` (colours, springs, transitions, button styles), `Events.swift` (event wording, JSON helpers), `HTTP.swift` (tiny HTTP server), `Hooks.swift` (hook server, Allow/Deny), `Prompts.swift`, `Activity.swift` (edit panel and steps), `Diff.swift` (line diff, highlighting, diff view), `Context.swift` (context ring), `Sessions.swift`, `Music.swift`, `VSCode.swift`, `Tabs.swift`, `Settings.swift`, `Tray.swift` (menu bar icon), `Pair.swift` (pairing window and QR), `Phone.swift` (iPhone server), `MacOS.swift` (AppleScript, process and file helpers).
- `Tests/QaqashTests/`: diff and pairing-code checks (`swift test`).
- `scripts/run.sh`: builds, bundles `build/Qaqash.app`, signs it with the Apple Development identity (so macOS permissions survive rebuilds) and relaunches it. `scripts/run.sh release` for a release build.

## Rules for working here
- Run and test locally (`scripts/run.sh`, `swift test`). Prefer verifying the notch look on screen over assuming.
- Do not edit `~/.claude/settings.json` without asking. Provide `claude-hooks.example.json` and let the user merge it.
- Keep it offline-only. No telemetry, no network calls beyond 127.0.0.1. One exception the user approved: Spotify cover images load from `https://i.scdn.co` (checked in the frontend before use). The paired iPhone reaches the Mac over the local Wi-Fi.
- Music (Spotify, Apple Music) is read and controlled with local AppleScript (`NSAppleScript`, all on the `scripts` queue). Only query an app after `NSRunningApplication` confirms it is running, so Qaqash never launches a music app on its own; only the user's click on play or the cover may start Spotify. Apple Music art is read locally; Apple Music radio has no track info, so it shows as "Apple Music Radio".
- Stay quiet while the Claude desktop app (`com.anthropic.claudefordesktop`) is frontmost: no prompts, no sounds.

## Build order
1. Scaffold the project and get a transparent island showing at the top centre.
2. Hook server + status text.
3. Allow/Deny round trip with a real Claude Code session.
4. Polish: animation, sound on Stop, multiple pending requests, stale request cleanup if the hook process dies.
5. Later, optional: local chat via Ollama, local dictation.
