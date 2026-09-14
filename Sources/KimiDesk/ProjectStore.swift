import CryptoKit
import Foundation
import Observation
import AppKit

struct Project: Identifiable, Hashable {
    var path: String          // id
    var displayName: String
    var favorite: Bool = false
    var group: String?        // nil = 未分组
    var yolo: Bool = false    // 自动批准所有操作，不再逐条确认
    var lastOpenedAt: Date?

    var id: String { path }

    /// The backing folder no longer exists on disk.
    var isMissing: Bool {
        var isDir: ObjCBool = false
        return !(FileManager.default.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue)
    }

    /// Number of sessions recorded on disk by kimi-cli for this work dir.
    var sessionCount: Int {
        let dir = Self.sessionsDir(for: path)
        let items = (try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        )) ?? []
        return items.filter { $0.hasDirectoryPath }.count
    }

    static func sessionsDir(for path: String) -> URL {
        let digest = Insecure.MD5.hash(data: Data(path.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".kimi/sessions/\(hex)")
    }
}

/// Merges kimi-cli's own work-dir index (~/.kimi/kimi.json) with display
/// metadata kept by this app (projects.json / groups.json).
/// Never mutates kimi-cli data.
@Observable
@MainActor
final class ProjectStore {
    private(set) var projects: [Project] = []
    private(set) var groups: [String] = []   // ordered group names

    /// 默认项目目录（+ 号直接用它建项目，不弹窗）
    private(set) var defaultDir: String = UserDefaults.standard.string(forKey: "defaultProjectDir")
        ?? "/Users/jackywang/Documents/kimi/Default_Project"

    /// 是否自动导入终端里用过的目录（~/.kimi/kimi.json）。默认关闭：只显示手动 + 添加的。
    private(set) var autoImport: Bool = UserDefaults.standard.bool(forKey: "autoImportKimiHistory")

    func setAutoImport(_ value: Bool) {
        autoImport = value
        UserDefaults.standard.set(value, forKey: "autoImportKimiHistory")
        load()
    }

    func setDefaultDir(_ path: String) {
        defaultDir = path
        UserDefaults.standard.set(path, forKey: "defaultProjectDir")
    }

    func setDefaultDirViaPanel() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "设为默认目录"
        if panel.runModal() == .OK, let url = panel.url {
            setDefaultDir(url.standardizedFileURL.path)
        }
    }

    /// + 号：直接用默认目录建项目（目录不存在则创建），已存在则只返回它。
    @discardableResult
    func addDefault() -> Project? {
        let dir = defaultDir
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        if let existing = projects.first(where: { $0.path == dir }) { return existing }
        add(path: dir)
        return projects.first(where: { $0.path == dir })
    }

    /// 开聊前更换项目目录（path 是项目 id，需要迁移元数据）。
    func changePath(of project: Project, to newPath: String) {
        let newPath = URL(fileURLWithPath: newPath).standardizedFileURL.path
        guard newPath != project.path,
              !projects.contains(where: { $0.path == newPath }) else { return }
        guard let idx = projects.firstIndex(where: { $0.path == project.path }) else { return }
        var p = projects[idx]
        let oldPath = p.path
        // 显示名若还是旧目录名，跟着更新
        if p.displayName == URL(fileURLWithPath: oldPath).lastPathComponent {
            p.displayName = URL(fileURLWithPath: newPath).lastPathComponent
        }
        p.path = newPath
        projects[idx] = p
        // 迁移 projects.json 里的元数据键
        var metas: [String: Meta] = [:]
        if let data = try? Data(contentsOf: metaFile),
           let decoded = try? JSONDecoder().decode([String: Meta].self, from: data) {
            metas = decoded
        }
        if let old = metas.removeValue(forKey: oldPath) {
            metas[newPath] = old
            if let data = try? JSONEncoder().encode(metas) {
                try? data.write(to: metaFile, options: .atomic)
            }
        }
        persistAll()
    }

    private struct Meta: Codable {
        var displayName: String?
        var favorite: Bool?
        var group: String??
        var yolo: Bool?
        var hidden: Bool?
        var lastOpenedAt: Date?
        var addedManually: Bool?
    }

    private var metaFile: URL {
        ServerManager.appSupportDir().appendingPathComponent("projects.json")
    }
    private var groupsFile: URL {
        ServerManager.appSupportDir().appendingPathComponent("groups.json")
    }

    // MARK: - load / save

    func load() {
        var metas: [String: Meta] = [:]
        if let data = try? Data(contentsOf: metaFile),
           let decoded = try? JSONDecoder().decode([String: Meta].self, from: data) {
            metas = decoded
        }
        if let data = try? Data(contentsOf: groupsFile),
           let decoded = try? JSONDecoder().decode([String].self, from: data) {
            groups = decoded
        }

        var paths = Set<String>()

        // 1) work dirs already known to kimi-cli（仅当开启自动导入）
        if autoImport {
            let kimiJSON = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".kimi/kimi.json")
            struct KimiJSON: Decodable {
                struct WorkDir: Decodable { let path: String; let kaos: String? }
                let work_dirs: [WorkDir]
            }
            if let data = try? Data(contentsOf: kimiJSON),
               let decoded = try? JSONDecoder().decode(KimiJSON.self, from: data) {
                for wd in decoded.work_dirs where wd.kaos == nil || wd.kaos == "local" {
                    paths.insert(wd.path)
                }
            }
        }

        // 2) 用户手动维护的项目：projects.json 里所有未隐藏的条目。
        // （之前靠 addedManually 标志，但它会被后续的 persistAll 覆盖丢失）
        for (path, meta) in metas where meta.hidden != true {
            paths.insert(path)
        }

        var knownGroups = Set(groups)
        projects = paths.compactMap { path in
            let meta = metas[path]
            guard meta?.hidden != true else { return nil }
            let group = meta?.group ?? nil
            if let group { knownGroups.insert(group) }
            return Project(
                path: path,
                displayName: meta?.displayName ?? URL(fileURLWithPath: path).lastPathComponent,
                favorite: meta?.favorite ?? false,
                group: group,
                yolo: meta?.yolo ?? false,
                lastOpenedAt: meta?.lastOpenedAt
            )
        }
        // groups discovered from project metas but missing from the order list
        for g in knownGroups where !groups.contains(g) { groups.append(g) }
        sortProjects()
    }

    private func persistAll() {
        var metas: [String: Meta] = [:]
        // preserve hidden entries from disk
        if let data = try? Data(contentsOf: metaFile),
           let old = try? JSONDecoder().decode([String: Meta].self, from: data) {
            for (path, meta) in old where meta.hidden == true {
                metas[path] = meta
            }
        }
        for p in projects {
            metas[p.path] = Meta(
                displayName: p.displayName,
                favorite: p.favorite,
                group: .some(p.group),
                yolo: p.yolo,
                hidden: false,
                lastOpenedAt: p.lastOpenedAt,
                addedManually: nil
            )
        }
        if let data = try? JSONEncoder().encode(metas) {
            try? data.write(to: metaFile, options: .atomic)
        }
        if let data = try? JSONEncoder().encode(groups) {
            try? data.write(to: groupsFile, options: .atomic)
        }
    }

    // MARK: - project ops

    func add(path: String) {
        let normalized = URL(fileURLWithPath: path).standardizedFileURL.path
        guard !projects.contains(where: { $0.path == normalized }) else { return }
        projects.append(Project(path: normalized, displayName: URL(fileURLWithPath: normalized).lastPathComponent))
        sortProjects()
        persistAll()
    }

    func addViaPanel() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "添加项目"
        if panel.runModal() == .OK, let url = panel.url {
            add(path: url.path)
        }
    }

    func toggleFavorite(_ project: Project) {
        mutate(project) { $0.favorite.toggle() }
    }

    func rename(_ project: Project, to name: String) {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        mutate(project) { $0.displayName = name }
    }

    func setGroup(_ project: Project, to group: String?) {
        mutate(project) { $0.group = group }
    }

    func toggleYolo(_ project: Project) {
        mutate(project) { $0.yolo.toggle() }
    }

    /// 把 yolo 标记写进会话的 state.json（kimi-cli 启动 worker 时会读取
    /// session.state.approval.yolo）。合并写入，不动其他字段。
    static func patchSessionYolo(workDir: String, sessionID: String, yolo: Bool) {
        let f = Project.sessionsDir(for: workDir)
            .appendingPathComponent(sessionID)
            .appendingPathComponent("state.json")
        var dict: [String: Any] = [:]
        if let data = try? Data(contentsOf: f),
           let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            dict = existing
        }
        var approval = dict["approval"] as? [String: Any] ?? [:]
        approval["yolo"] = yolo
        dict["approval"] = approval
        if dict["version"] == nil { dict["version"] = 1 }
        if let data = try? JSONSerialization.data(withJSONObject: dict) {
            try? data.write(to: f, options: .atomic)
        }
    }

    func markOpened(_ project: Project) {
        mutate(project, persist: false) { $0.lastOpenedAt = Date() }
    }

    /// Hide from our sidebar only; kimi-cli's own data is untouched.
    func remove(_ project: Project) {
        remove(paths: [project.path])
    }

    func remove(paths: Set<String>) {
        projects.removeAll { paths.contains($0.path) }
        // mark hidden on disk
        var metas: [String: Meta] = [:]
        if let data = try? Data(contentsOf: metaFile),
           let decoded = try? JSONDecoder().decode([String: Meta].self, from: data) {
            metas = decoded
        }
        for path in paths {
            var meta = metas[path] ?? Meta()
            meta.hidden = true
            meta.addedManually = false
            metas[path] = meta
        }
        if let data = try? JSONEncoder().encode(metas) {
            try? data.write(to: metaFile, options: .atomic)
        }
    }

    /// Remove every project whose backing folder no longer exists.
    /// Safety fuse: if MORE THAN HALF of all projects look missing, something
    /// is wrong (e.g. file-access denial making every check fail, or an
    /// unmounted drive) — refuse instead of wiping the whole list.
    /// - Returns: paths that were removed (for confirmation messaging).
    @discardableResult
    func cleanupMissing() -> [String] {
        let missing = Set(projects.filter { $0.isMissing }.map { $0.path })
        guard !missing.isEmpty else { return [] }
        if missing.count == projects.count || missing.count * 2 > projects.count {
            return [] // 异常：超过一半项目都“失效”，拒绝执行
        }
        remove(paths: missing)
        return Array(missing)
    }

    /// True when the missing ratio is suspiciously high (fuse would block cleanup).
    var cleanupSuspicious: Bool {
        guard !projects.isEmpty else { return false }
        return missingCount == projects.count || missingCount * 2 > projects.count
    }

    var missingCount: Int {
        projects.filter { $0.isMissing }.count
    }

    // MARK: - group ops

    func createGroup(_ name: String) {
        let name = name.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, !groups.contains(name) else { return }
        groups.append(name)
        persistAll()
    }

    func renameGroup(_ old: String, to new: String) {
        let new = new.trimmingCharacters(in: .whitespaces)
        guard !new.isEmpty, old != new, !groups.contains(new) else { return }
        guard let idx = groups.firstIndex(of: old) else { return }
        groups[idx] = new
        for i in projects.indices where projects[i].group == old {
            projects[i].group = new
        }
        persistAll()
    }

    /// Delete the group; its projects fall back to ungrouped.
    func deleteGroup(_ name: String) {
        groups.removeAll { $0 == name }
        for i in projects.indices where projects[i].group == name {
            projects[i].group = nil
        }
        persistAll()
    }

    // MARK: - helpers

    func projects(inGroup group: String?) -> [Project] {
        sorted(projects.filter { $0.group == group && !$0.favorite })
    }

    var favorites: [Project] {
        sorted(projects.filter { $0.favorite })
    }

    private func mutate(_ project: Project, persist: Bool = true, _ change: (inout Project) -> Void) {
        guard let idx = projects.firstIndex(where: { $0.path == project.path }) else { return }
        change(&projects[idx])
        if persist { persistAll() }
    }

    private func sortProjects() {
        projects = sorted(projects)
    }

    private func sorted(_ list: [Project]) -> [Project] {
        list.sorted {
            switch ($0.lastOpenedAt, $1.lastOpenedAt) {
            case let (a?, b?): return a > b
            case (_?, nil): return true
            case (nil, _?): return false
            default: return $0.displayName.localizedCompare($1.displayName) == .orderedAscending
            }
        }
    }
}
