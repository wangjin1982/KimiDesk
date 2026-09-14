# KimiDesk

**English → [README.md](README.md)**

[Kimi Code CLI](https://moonshotai.github.io/kimi-cli/) 的原生 macOS 桌面客户端——图形界面 + 项目管理，从此用 Kimi Code 不用再开终端。

> ⚠️ 需要先安装 [kimi-cli](https://github.com/MoonshotAI/kimi-cli) ≥ 1.50 并完成登录（`kimi login`）。

## 为什么做这个

Kimi 官方桌面 App 用的是对话模型的额度，而 **Kimi Code**（编程 agent 额度）只能在终端里用。KimiDesk 补上这个缺口：独立 App 窗口、类似 ZCode/Cursor 的项目侧栏、按项目记录会话。

## 功能

- **原生 macOS App**——独立 Dock 图标，自动拉起内置的 `kimi web` 后端（随机端口 + 每次启动随机 token，仅监听本机回环）
- **项目侧栏**——默认只显示手动 ＋ 添加的项目（可在 ⋯ 菜单开启「自动导入终端历史项目」）；支持收藏、可折叠分组、⌘多选批量删除、一键清理文件夹已不存在的失效项目（占比过半时拒绝执行，防止外置盘未挂载误清）
- **一键建项目**——＋ 号直接在默认目录（`~/Documents/kimi/Default_Project`，可改）建项目，不弹窗
- **开聊前可改目录**——新会话顶部显示路径条，发出第一条消息后自动隐藏
- **会话恢复**——点项目自动恢复最近一次会话（没有则新建），会话存在 `~/.kimi/sessions/`，重启不丢
- **项目文件面板**——查看 agent 生成的文件（如 md 报告），每 5 秒自动刷新；支持 QuickLook 预览 / 打开 / 在 Finder 中显示
- **额度一目了然**——工具栏仪表盘（绿/橙/红），点开看 7 天用量、5 小时用量、重置倒计时、会员等级，每 5 分钟自动刷新
- **按项目开启 yolo**——右键项目 →「自动批准所有操作 (yolo)」：该项目的会话自动批准所有工具调用，不再逐条询问（写入会话的 `state.json`，kimi-cli worker 启动时读取生效）
- **永不过时**——聊天界面就是 kimi-cli 官方 Web 前端原样内嵌，升级 = `uv tool upgrade kimi-cli`

## 安装

从 [Releases](../../releases) 下载 `KimiDesk-*-universal.zip`，解压后拖入「应用程序」。首次打开：**右键 → 打开**（adhoc 签名，未公证）。

## 从源码构建

```bash
swift build          # 调试构建
./Scripts/dist.sh    # universal 构建 + .app + 图标 + adhoc 签名 + zip（产物在 Dist/）
```

## 工作原理

```
KimiDesk.app (SwiftUI)
├── ServerManager   托管 kimi web 子进程（健康检查、崩溃重启、REST 客户端）
├── ProjectStore    projects.json + groups.json（只存显示层元数据，绝不动 kimi-cli 的数据）
├── UsageManager    读 ~/.kimi/credentials/kimi-code.json → GET api.kimi.com/coding/v1/usages
├── ContentView     NavigationSplitView：侧栏 + 会话解析流程
├── FileListView    文件面板（inspector 列）+ QuickLook
└── WebView         WKWebView 内嵌官方 kimi web SPA
                   （深链：?token=…&session=<id>）
```

会话深链用的是官方 SPA 自带的 URL 契约：`?token=` 存入 localStorage，`?session=<id>` 启动时直接恢复。

## 数据与隐私

- KimiDesk 只在 `~/Library/Application Support/KimiDesk/` 存显示层元数据（名称、收藏、分组）
- 所有对话记录都在 `~/.kimi/sessions/`，归 kimi-cli 管
- 后端仅监听 127.0.0.1，每次启动使用随机 bearer token

## 许可证

MIT
