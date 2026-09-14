import SwiftUI

struct ContentView: View {
    @Environment(ServerManager.self) private var server
    @Environment(ProjectStore.self) private var store
    @Environment(UsageManager.self) private var usage

    @State private var selection: Set<String> = []
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var renaming: Project?
    @State private var renameText = ""
    @State private var resolvedURL: URL?
    @State private var resolving = false
    @State private var resolveError: String?

    @State private var showNewGroup = false
    @State private var newGroupName = ""
    @State private var renamingGroup: String?
    @State private var renameGroupText = ""
    @State private var showCleanupConfirm = false
    @State private var showFiles = false
    @State private var conversationStarted = false
    @State private var currentSessionID: String?

    /// The single project shown in the detail pane (last clicked).
    private var activePath: String? {
        selection.count == 1 ? selection.first : nil
    }


    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar
                .navigationSplitViewColumnWidth(min: 200, ideal: 250, max: 400)
                .navigationTitle("Kimi 项目")
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        QuotaButton()
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            if let p = store.addDefault() {
                                selection = [p.path]
                            }
                        } label: {
                            Image(systemName: "plus")
                        }
                        .help("新建项目（默认目录：\(store.defaultDir)）")
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            Button("新建分组…") { showNewGroup = true }
                            Divider()
                            Button("更改默认项目目录…") { store.setDefaultDirViaPanel() }
                            Toggle("自动导入终端历史项目", isOn: Binding(
                                get: { store.autoImport },
                                set: { store.setAutoImport($0) }
                            ))
                            Button("清理失效项目（文件夹已不存在）…") { showCleanupConfirm = true }
                                .disabled(store.missingCount == 0)
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                        .help("更多操作")
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            showFiles.toggle()
                        } label: {
                            Image(systemName: "doc.text.magnifyingglass")
                        }
                        .help("查看项目文件")
                        .disabled(activePath == nil)
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    ServerStatusView(state: server.state, port: server.port)
                }
        } detail: {
            detailView
        }
        .onAppear {
            // 系统会记住上次的侧栏折叠状态并覆盖初始值；每次启动强制展开
            columnVisibility = .all
        }
        .onChange(of: selection) { _, newValue in
            if let path = activePath,
               let project = store.projects.first(where: { $0.path == path }) {
                store.markOpened(project)
            }
            resolveSession(for: activePath)
        }
        .onChange(of: server.state) { _, newState in
            if newState == .running { resolveSession(for: activePath) }
        }
        .alert("重命名项目", isPresented: Binding(
            get: { renaming != nil },
            set: { if !$0 { renaming = nil } }
        )) {
            TextField("显示名", text: $renameText)
            Button("取消", role: .cancel) { renaming = nil }
            Button("确定") {
                if let p = renaming { store.rename(p, to: renameText) }
                renaming = nil
            }
        }
        .alert("新建分组", isPresented: $showNewGroup) {
            TextField("分组名", text: $newGroupName)
            Button("取消", role: .cancel) { newGroupName = "" }
            Button("创建") {
                store.createGroup(newGroupName)
                newGroupName = ""
            }
        }
        .alert("重命名分组", isPresented: Binding(
            get: { renamingGroup != nil },
            set: { if !$0 { renamingGroup = nil } }
        )) {
            TextField("分组名", text: $renameGroupText)
            Button("取消", role: .cancel) { renamingGroup = nil }
            Button("确定") {
                if let g = renamingGroup { store.renameGroup(g, to: renameGroupText) }
                renamingGroup = nil
            }
        }
        .alert("清理失效项目", isPresented: $showCleanupConfirm) {
            Button("取消", role: .cancel) {}
            Button("移除 \(store.missingCount) 个", role: .destructive) {
                let removed = Set(store.cleanupMissing())
                selection.subtract(removed)
            }
        } message: {
            let missing = store.projects.filter { $0.isMissing }
            let preview = missing.prefix(8).map { "· \($0.displayName)" }.joined(separator: "\n")
            let rest = missing.count > 8 ? "\n… 以及另外 \(missing.count - 8) 个" : ""
            let warning = store.cleanupSuspicious
                ? "⚠️ 失效项目占比异常高，可能是外置盘未挂载或文件权限问题，请先到 Finder 确认后再手动移除。\n\n"
                : ""
            Text("\(warning)共 \(missing.count) 个项目的文件夹已不存在，将从列表移除（kimi-cli 的会话记录不受影响）：\n\n\(preview)\(rest)")
        }
    }

    // MARK: - sidebar

    @ViewBuilder
    private var sidebar: some View {
        List(selection: $selection) {
            if !store.favorites.isEmpty {
                Section("收藏") {
                    ForEach(store.favorites, content: projectRow)
                }
            }
            ForEach(store.groups, id: \.self) { group in
                DisclosureGroup {
                    ForEach(store.projects(inGroup: group), content: projectRow)
                } label: {
                    Label(group, systemImage: "folder.fill")
                        .contextMenu {
                            Button("重命名分组…") {
                                renamingGroup = group
                                renameGroupText = group
                            }
                            Button("删除分组（项目回到未分组）", role: .destructive) {
                                let affected = Set(store.projects(inGroup: group).map(\.path))
                                store.deleteGroup(group)
                                // keep selection valid
                                selection.formIntersection(Set(store.projects.map(\.path)).union(affected))
                            }
                        }
                }
            }
            Section(store.groups.isEmpty ? "" : "未分组") {
                ForEach(store.projects(inGroup: nil), content: projectRow)
            }
        }
        .listStyle(.sidebar)
        .onDeleteCommand {
            let sel = selection
            guard !sel.isEmpty else { return }
            store.remove(paths: sel)
            selection = []
        }
    }

    @ViewBuilder
    private func projectRow(_ project: Project) -> some View {
        ProjectRow(project: project)
            .tag(project.path)
            .contextMenu {
                if selection.count > 1, selection.contains(project.path) {
                    Button("移除 \(selection.count) 个项目", role: .destructive) {
                        store.remove(paths: selection)
                        selection = []
                    }
                } else {
                    Button(project.favorite ? "取消收藏" : "收藏") {
                        store.toggleFavorite(project)
                    }
                    Button(project.yolo ? "关闭自动批准 (yolo)" : "自动批准所有操作 (yolo)") {
                        store.toggleYolo(project)
                        // 立即作用到当前会话
                        if let sid = currentSessionID, activePath == project.path {
                            ProjectStore.patchSessionYolo(workDir: project.path, sessionID: sid, yolo: !project.yolo)
                        }
                    }
                    Menu("移动到分组") {
                        Button("未分组") { store.setGroup(project, to: nil) }
                        ForEach(store.groups, id: \.self) { g in
                            Button(g) { store.setGroup(project, to: g) }
                        }
                        Divider()
                        Button("新建分组…") { showNewGroup = true }
                    }
                    Button("重命名…") {
                        renaming = project
                        renameText = project.displayName
                    }
                    Button("在 Finder 中显示") {
                        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: project.path)
                    }
                    .disabled(project.isMissing)
                    Divider()
                    Button("从列表移除", role: .destructive) {
                        selection.remove(project.path)
                        store.remove(project)
                    }
                }
            }
    }

    // MARK: - detail

    @ViewBuilder
    private var detailView: some View {
        switch server.state {
        case .failed(let message):
            ContentUnavailableView {
                Label("后端未运行", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("重试") { server.start() }
            }
        case .starting, .stopped:
            VStack(spacing: 12) {
                ProgressView()
                Text("正在启动 kimi web 服务…")
                    .foregroundStyle(.secondary)
            }
        case .running:
            if selection.count > 1 {
                ContentUnavailableView {
                    Label("已选择 \(selection.count) 个项目", systemImage: "checkmark.circle")
                } actions: {
                    Button("移除这 \(selection.count) 个项目", role: .destructive) {
                        store.remove(paths: selection)
                        selection = []
                    }
                }
            } else if let path = activePath {
                if resolving {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("正在打开会话…").foregroundStyle(.secondary)
                    }
                } else if let resolveError {
                    ContentUnavailableView {
                        Label("无法打开项目", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(resolveError)
                    } actions: {
                        Button("重试") { resolveSession(for: path) }
                    }
                } else {
                    VStack(spacing: 0) {
                        // 开聊前显示路径条，可更改目录；开聊后自动隐藏
                        if !conversationStarted {
                            HStack(spacing: 8) {
                                Image(systemName: "folder")
                                    .foregroundStyle(.secondary)
                                Text(path)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Spacer()
                                Button("更改目录…") { changeDirectory(of: path) }
                                    .controlSize(.small)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(.bar)
                        }
                        WebView(url: resolvedURL)
                            .id(path) // force reload when switching projects
                    }
                    .navigationTitle(store.projects.first(where: { $0.path == path })?.displayName ?? path)
                    .inspector(isPresented: $showFiles) {
                        FileListView(dirPath: path)
                            .inspectorColumnWidth(min: 220, ideal: 260, max: 400)
                    }
                    .task(id: conversationStarted ? nil : currentSessionID) {
                        // 未开聊时每 3 秒检查一次：context.jsonl 一旦有内容即隐藏路径条
                        guard !conversationStarted, currentSessionID != nil else { return }
                        while !Task.isCancelled && !conversationStarted {
                            try? await Task.sleep(for: .seconds(3))
                            checkConversationStarted(for: path)
                        }
                    }
                }
            } else {
                ContentUnavailableView("选择一个项目开始",
                                       systemImage: "folder.badge.plus",
                                       description: Text("左侧选择或新增一个项目目录；⌘点选可批量操作"))
            }
        }
    }

    /// Resolve the latest on-disk session for the project via the kimi web API,
    /// creating one if none exists, then point the web view at it.
    private func resolveSession(for path: String?) {
        resolvedURL = nil
        resolveError = nil
        currentSessionID = nil
        conversationStarted = false
        guard let path, server.state == .running else { resolving = false; return }
        resolving = true
        Task {
            var sessionID = await server.latestSessionID(forWorkDir: path)
            if sessionID == nil {
                do {
                    sessionID = try await server.createSession(workDir: path)
                } catch {
                    await MainActor.run {
                        resolving = false
                        resolveError = "目录可能已被移动或删除：\(error.localizedDescription)"
                    }
                    return
                }
            }
            await MainActor.run {
                resolving = false
                if let sessionID {
                    // yolo 项目：把标记写进 state.json，worker 启动时生效
                    if let project = store.projects.first(where: { $0.path == path }), project.yolo {
                        ProjectStore.patchSessionYolo(workDir: path, sessionID: sessionID, yolo: true)
                    }
                    resolvedURL = server.sessionURL(id: sessionID)
                    currentSessionID = sessionID
                    checkConversationStarted(for: path)
                }
            }
        }
    }

    /// 开聊判定：会话的 context.jsonl 非空（新建的空会话为 0 字节）。
    private func checkConversationStarted(for path: String) {
        guard let sid = currentSessionID else { conversationStarted = false; return }
        let f = Project.sessionsDir(for: path).appendingPathComponent(sid).appendingPathComponent("context.jsonl")
        let attrs = try? FileManager.default.attributesOfItem(atPath: f.path)
        let size = (attrs?[.size] as? Int) ?? 0
        conversationStarted = size > 0
    }

    /// 开聊前更换项目目录：迁移项目，丢弃旧目录下的空会话，重新解析。
    private func changeDirectory(of path: String) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "选择"
        panel.directoryURL = URL(fileURLWithPath: path)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let newPath = url.standardizedFileURL.path
        guard let project = store.projects.first(where: { $0.path == path }) else { return }
        let oldSession = currentSessionID
        store.changePath(of: project, to: newPath)
        selection = [newPath]
        if let oldSession {
            Task { await server.deleteSession(id: oldSession) }
        }
    }
}

private struct ProjectRow: View {
    let project: Project

    var body: some View {
        HStack {
            Image(systemName: project.favorite ? "star.fill" : "folder")
                .foregroundStyle(project.favorite ? .yellow : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(project.displayName)
                        .lineLimit(1)
                    if project.yolo {
                        Image(systemName: "bolt.fill")
                            .font(.caption2)
                            .foregroundStyle(.purple)
                            .help("yolo：自动批准所有操作")
                    }
                    if project.isMissing {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                            .help("文件夹已不存在")
                    }
                }
                Text(project.path)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            Spacer()
            let count = project.sessionCount
            if count > 0 {
                Text("\(count)")
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
                    .help("\(count) 个历史会话")
            }
        }
        .opacity(project.isMissing ? 0.6 : 1)
    }
}

private struct ServerStatusView: View {
    let state: ServerManager.State
    let port: Int

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var color: Color {
        switch state {
        case .running: .green
        case .starting: .orange
        case .stopped: .gray
        case .failed: .red
        }
    }

    private var text: String {
        switch state {
        case .running: "kimi web · :\(port)"
        case .starting: "启动中…"
        case .stopped: "已停止"
        case .failed: "后端异常"
        }
    }
}

// MARK: - 额度显示

private struct QuotaButton: View {
    @Environment(UsageManager.self) private var usage
    @State private var showPopover = false

    var body: some View {
        Button {
            showPopover.toggle()
            Task { await usage.refresh() }
        } label: {
            Image(systemName: "gauge.with.needle")
                .foregroundStyle(color)
        }
        .help("套餐额度")
        .popover(isPresented: $showPopover, arrowEdge: .bottom) {
            QuotaPopover()
        }
    }

    private var color: Color {
        switch usage.worstRatio {
        case ..<0.5: .green
        case ..<0.8: .orange
        default: .red
        }
    }
}

private struct QuotaPopover: View {
    @Environment(UsageManager.self) private var usage

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Kimi Code 额度")
                    .font(.headline)
                if let m = usage.membership {
                    Text(m)
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                }
                Spacer()
                Button {
                    Task { await usage.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("刷新")
            }

            if let error = usage.error, usage.windows.isEmpty {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else if usage.windows.isEmpty {
                Text("暂无额度数据").foregroundStyle(.secondary)
            } else {
                ForEach(usage.windows) { w in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(w.label).font(.subheadline)
                            Spacer()
                            Text("剩 \(w.remaining) / \(w.limit)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        ProgressView(value: w.ratio)
                            .tint(w.ratio > 0.8 ? .red : w.ratio > 0.5 ? .orange : .accentColor)
                        if let reset = w.resetAt {
                            (Text(reset, style: .relative) + Text("后重置"))
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }

            if let t = usage.lastUpdated {
                Text("更新于 ") + Text(t, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding()
        .frame(width: 280)
    }
}
