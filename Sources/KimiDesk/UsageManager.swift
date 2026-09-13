import Foundation
import Observation

/// Fetches Kimi Code plan quota from https://api.kimi.com/coding/v1/usages
/// using the OAuth access token that kimi-cli persists at
/// ~/.kimi/credentials/kimi-code.json (kept fresh by the running `kimi web`).
@Observable
@MainActor
final class UsageManager {
    struct QuotaWindow: Identifiable {
        let id = UUID()
        let label: String        // e.g. "5 小时用量" / "7 天用量"
        let used: Int
        let limit: Int
        let resetAt: Date?

        var remaining: Int { max(limit - used, 0) }
        var ratio: Double { limit > 0 ? min(Double(used) / Double(limit), 1) : 0 }
    }

    private(set) var windows: [QuotaWindow] = []
    private(set) var membership: String?
    private(set) var lastUpdated: Date?
    private(set) var error: String?

    private var timer: Task<Void, Never>?

    /// Worst ratio across windows — for the compact toolbar indicator.
    var worstRatio: Double { windows.map(\.ratio).max() ?? 0 }

    func start() {
        guard timer == nil else { return }
        timer = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: .seconds(300)) // 每 5 分钟
            }
        }
    }

    func refresh() async {
        guard let token = Self.loadAccessToken() else {
            error = "未找到登录凭证（请先 kimi login）"
            return
        }
        var req = URLRequest(url: URL(string: "https://api.kimi.com/coding/v1/usages")!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 10
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard (resp as? HTTPURLResponse)?.statusCode == 200 else {
                error = "查询失败（HTTP \((resp as? HTTPURLResponse)?.statusCode ?? -1)）"
                return
            }
            try parse(data)
            error = nil
            lastUpdated = Date()
        } catch {
            self.error = "查询失败：\(error.localizedDescription)"
        }
    }

    // MARK: - parsing

    private func parse(_ data: Data) throws {
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        var result: [QuotaWindow] = []

        if let usage = root["usage"] as? [String: Any],
           let row = Self.row(from: usage, label: "7 天用量") {
            result.append(row)
        }
        if let limits = root["limits"] as? [[String: Any]] {
            for item in limits {
                let detail = (item["detail"] as? [String: Any]) ?? item
                let window = item["window"] as? [String: Any] ?? [:]
                let label = Self.windowLabel(item: item, detail: detail, window: window)
                if let row = Self.row(from: detail, label: label) {
                    result.append(row)
                }
            }
        }
        if let total = root["totalQuota"] as? [String: Any], !total.isEmpty,
           let row = Self.row(from: total, label: "总使用量") {
            result.insert(row, at: 0)
        }
        windows = result

        if let user = root["user"] as? [String: Any],
           let m = user["membership"] as? [String: Any],
           let level = m["level"] as? String {
            membership = switch level {
            case "LEVEL_INTERMEDIATE": "中级会员"
            case "LEVEL_PREMIUM": "高级会员"
            case "LEVEL_FREE": "免费版"
            default: level
            }
        }
    }

    private static func row(from dict: [String: Any], label: String) -> QuotaWindow? {
        guard let limit = intVal(dict["limit"]) else { return nil }
        let used = intVal(dict["used"])
            ?? (intVal(dict["remaining"]).map { limit - $0 })
            ?? 0
        var resetAt: Date? = nil
        if let s = dict["resetTime"] as? String {
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            resetAt = f.date(from: s)
        }
        return QuotaWindow(label: label, used: used, limit: limit, resetAt: resetAt)
    }

    private static func windowLabel(item: [String: Any], detail: [String: Any],
                                    window: [String: Any]) -> String {
        for key in ["name", "title", "scope"] {
            if let v = (item[key] ?? detail[key]) as? String, !v.isEmpty { return v }
        }
        if let duration = intVal(window["duration"] ?? item["duration"] ?? detail["duration"]) {
            let unit = (window["timeUnit"] ?? item["timeUnit"] ?? detail["timeUnit"]) as? String ?? ""
            if unit.contains("MINUTE") {
                if duration >= 60, duration % 60 == 0 { return "\(duration / 60) 小时用量" }
                return "\(duration) 分钟用量"
            }
            if unit.contains("HOUR") { return "\(duration) 小时用量" }
            if unit.contains("DAY") { return "\(duration) 天用量" }
        }
        return "限额"
    }

    private static func intVal(_ v: Any?) -> Int? {
        if let i = v as? Int { return i }
        if let s = v as? String { return Int(s) }
        return nil
    }

    // MARK: - credentials

    private static func loadAccessToken() -> String? {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".kimi/credentials/kimi-code.json")
        guard let data = try? Data(contentsOf: url),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return dict["access_token"] as? String
    }
}
