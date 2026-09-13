# KimiDesk

**中文文档 → [README.zh-CN.md](README.zh-CN.md)**

A native macOS desktop app for [Kimi Code CLI](https://moonshotai.github.io/kimi-cli/) — a friendly GUI with project management, so you never have to open a terminal to use Kimi Code.

> ⚠️ Requires [kimi-cli](https://github.com/MoonshotAI/kimi-cli) ≥ 1.50 installed and logged in (`kimi login`).

## Why

The official Kimi desktop app chats with Kimi's conversational model, while **Kimi Code** (the coding-agent quota) only works in the terminal. KimiDesk bridges the gap: a native app window, a project sidebar like ZCode/Cursor, and your Kimi Code sessions recorded per project.

## Features

- **Native macOS app** — own Dock icon, launches the bundled `kimi web` backend automatically (random port + per-launch auth token, loopback only)
- **Project sidebar** — only projects you add manually (auto-import of terminal history available as an opt-in toggle); favorites, collapsible groups, multi-select batch removal, one-click cleanup of stale projects whose folders no longer exist
- **One-click new project** — the ＋ button creates a project in your default directory (`~/Documents/kimi/Default_Project`, configurable) without any file dialog
- **Change directory before chatting** — a path bar shows above a fresh session; it hides automatically once the conversation starts
- **Session resume** — clicking a project resumes its latest session (or creates one); sessions persist in `~/.kimi/sessions/` across restarts
- **Project file panel** — browse files the agent generates (e.g. `.md` reports), auto-refreshed every 5s, with QuickLook preview / open / reveal in Finder
- **Quota at a glance** — toolbar gauge (green/orange/red) with a popover showing 7-day and 5-hour usage, reset countdown, and membership level; refreshes every 5 minutes
- **Always up to date** — the chat UI is the official kimi-cli web frontend embedded as-is; upgrading is just `uv tool upgrade kimi-cli`

## Install

Download `KimiDesk-*-universal.zip` from [Releases](../../releases), unzip, drag to `/Applications`. First launch: **right-click → Open** (the app is adhoc-signed, not notarized).

## Build from source

```bash
swift build          # debug build
./Scripts/dist.sh    # universal binary + .app + icon + adhoc sign + zip (in Dist/)
```

## How it works

```
KimiDesk.app (SwiftUI)
├── ServerManager   spawns/manages `kimi web` (health check, auto-restart, REST client)
├── ProjectStore    projects.json + groups.json (display metadata only — never touches kimi-cli data)
├── UsageManager    reads ~/.kimi/credentials/kimi-code.json → GET api.kimi.com/coding/v1/usages
├── ContentView     NavigationSplitView: sidebar + session resolution flow
├── FileListView    inspector column with project files + QuickLook
└── WebView         WKWebView embedding the official kimi web SPA
                   (deep links: ?token=…&session=<id>)
```

Session deep-linking uses the SPA's built-in URL contract: `?token=` is stored to localStorage and `?session=<id>` is restored eagerly on load.

## Data & privacy

- KimiDesk stores only display metadata (names, favorites, groups) in `~/Library/Application Support/KimiDesk/`
- All conversations live in `~/.kimi/sessions/` owned by kimi-cli
- The backend listens on 127.0.0.1 only, with a random bearer token per launch

## License

MIT
