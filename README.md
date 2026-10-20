# Peep

A small companion for [Claude Code](https://docs.claude.com/en/docs/claude-code) that lives in your Mac's notch. A pair of eyes shows what Claude is doing, and the notch grows like the iPhone's Dynamic Island when Claude needs you.

Everything runs on your Mac. No account, no cloud, no telemetry.

## What it does

- **Status at a glance:** the eyes change with Claude's mood: working, needs you, done.
- **Allow or Deny from the notch:** permission requests open in the island with round ✕ / ✓ buttons, so you don't have to switch windows.
- **Answer Claude's questions:** one question at a time, with the recommended option marked.
- **Sessions on hover:** hover the island to see every running Claude Code session and what it's doing. Click one to jump to its app.
- **Music:** shows what Spotify or Apple Music is playing, with the cover, tinted bars and playback controls.
- **Sounds:** a ping when Claude needs you, a chime when it's done.
- **Quiet in the Claude app:** while the Claude desktop app is in front, Peep stays out of the way.
- **iPhone link (in progress):** the Mac side can pair with an iPhone over your Wi-Fi with a QR code (menu bar icon → **Pair iPhone…**). The iPhone app is not built yet.

## Requirements

- macOS 14 or later, ideally a Mac with a notch
- [Rust](https://rustup.rs) and [Node.js](https://nodejs.org) 20+
- Claude Code

## Run it

```bash
npm install
npm run tauri dev
```

## Connect it to Claude Code

Peep listens to Claude Code through [hooks](https://docs.claude.com/en/docs/claude-code/hooks). Merge the entries from [`claude-hooks.example.json`](claude-hooks.example.json) into the `hooks` section of `~/.claude/settings.json`, and change the path to `scripts/hook.sh` to where you cloned this repo.

If Peep isn't running, the hook does nothing and Claude Code behaves normally.

## How it works

```
Claude Code ── hook.sh ──> Peep (127.0.0.1:47831) ──> the island
                              │
                              └── Wi-Fi (47832, TLS, paired) ──> iPhone
```

- `scripts/hook.sh` sends each hook event to Peep. For permission requests and questions, Peep holds the request until you answer, then replies to Claude Code.
- The window is a fixed transparent area at the top of the screen that lets clicks through everywhere except the island.
- Music is read with AppleScript, and only from apps that are already running, so Peep never launches them.

## Project layout

| Path | What's there |
|---|---|
| `src/` | The island's frontend (TypeScript), one file per feature |
| `src/styles/` | Styles, one file per feature |
| `src-tauri/src/` | The Rust backend: hook server, window, music, phone link, menu bar |
| `scripts/hook.sh` | The Claude Code hook |
| `pair.html` | The iPhone pairing window |

## Privacy

Peep makes no network calls beyond your own Mac and, once you pair a phone, your local Wi-Fi. The one exception: Spotify cover images are loaded from Spotify's image server (`i.scdn.co`).
