import Foundation
import Observation

/// Manages the `kimi web` child process: launch, health check, auto-restart.
@Observable
@MainActor
final class ServerManager {
    enum State: Equatable {
        case stopped
        case starting
        case running
        case failed(String)
    }

    private(set) var state: State = .stopped
    private(set) var port: Int = 5494
    let token: String = UUID().uuidString.filter { $0 != "-" }
                    + UUID().uuidString.filter { $0 != "-" }

    private var process: Process?
    private var restartTask: Task<Void, Never>?
    private var intentionalStop = false

    var baseURL: URL { URL(string: "http://127.0.0.1:\(port)")! }

    /// URL that opens a specific session in the SPA.
    func sessionURL(id: String) -> URL {
        var comps = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            URLQueryItem(name: "token", value: token),
            URLQueryItem(name: "session", value: id),
        ]
        return comps.url!
    }

    // MARK: - kimi web REST API

    struct APISession: Decodable {
        let session_id: String
        let work_dir: String
        let archived: Bool
        let last_updated: String
    }

    enum APIError: LocalizedError {
        case http(Int, String)
        var errorDescription: String? {
            switch self { case .http(let code, let body): "HTTP \(code): \(body.prefix(200))" }
        }
    }

    private func apiRequest(_ method: String, _ path: String, body: Data? = nil) async throws -> Data {
        var req = URLRequest(url: baseURL.appendingPathComponent(path))
        req.httpMethod = method
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let body {
            req.httpBody = body
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
        guard (200..<300).contains(code) else {
            throw APIError.http(code, String(data: data, encoding: .utf8) ?? "")
        }
        return data
    }

    /// Latest non-archived session whose work_dir exactly matches, if any.
    func latestSessionID(forWorkDir path: String) async -> String? {
        guard let data = try? await apiRequest("GET", "api/sessions/?limit=500"),
              let sessions = try? JSONDecoder().decode([APISession].self, from: data) else {
            return nil
        }
        let normSelf = normalize(path)
        return sessions
            .filter { !$0.archived && normalize($0.work_dir) == normSelf }
            .sorted { $0.last_updated > $1.last_updated }
            .first?.session_id
    }

    /// Create a new session in an existing directory. Throws if it fails
    /// (e.g. directory no longer exists).
    func createSession(workDir path: String) async throws -> String {
        struct Payload: Encodable { let work_dir: String; let create_dir: Bool }
        let payload = try JSONEncoder().encode(Payload(work_dir: path, create_dir: false))
        let data = try await apiRequest("POST", "api/sessions/", body: payload)
        struct Created: Decodable { let session_id: String }
        return try JSONDecoder().decode(Created.self, from: data).session_id
    }

    /// Delete a session (used to discard the empty session left behind when
    /// the user changes a project's directory before starting a conversation).
    func deleteSession(id: String) async {
        _ = try? await apiRequest("DELETE", "api/sessions/\(id)")
    }

    /// macOS may report /tmp-style paths differently than kimi-cli stored them.
    private func normalize(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path
    }

    func start() {
        guard process == nil else { return }
        intentionalStop = false
        guard let kimiPath = Self.findKimiBinary() else {
            state = .failed("找不到 kimi 命令（请先安装 kimi-cli）")
            return
        }
        guard let freePort = Self.findFreePort(from: 5494) else {
            state = .failed("5494-5504 端口均被占用")
            return
        }
        port = freePort
        state = .starting

        let logURL = Self.appSupportDir().appendingPathComponent("kimi-web.log")
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: kimiPath)
        proc.arguments = ["web", "--port", "\(freePort)", "--no-open", "--auth-token", token]
        if let handle = try? FileHandle(forWritingTo: {
            if !FileManager.default.fileExists(atPath: logURL.path) {
                FileManager.default.createFile(atPath: logURL.path, contents: nil)
            }
            return logURL
        }()) {
            proc.standardOutput = handle
            proc.standardError = handle
        }
        proc.terminationHandler = { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, !self.intentionalStop else { return }
                self.process = nil
                self.state = .failed("kimi web 意外退出，5 秒后自动重启…")
                self.restartTask?.cancel()
                self.restartTask = Task {
                    try? await Task.sleep(for: .seconds(5))
                    guard !Task.isCancelled else { return }
                    self.start()
                }
            }
        }
        do {
            try proc.run()
            process = proc
        } catch {
            state = .failed("启动失败：\(error.localizedDescription)")
            return
        }
        pollHealth()
    }

    func stop() {
        intentionalStop = true
        restartTask?.cancel()
        process?.terminate()
        process = nil
        state = .stopped
    }

    private func pollHealth() {
        Task { [weak self] in
            guard let self else { return }
            let url = self.baseURL.appendingPathComponent("healthz")
            for _ in 0..<60 { // up to ~18s
                if self.process == nil { return }
                if let (_, resp) = try? await URLSession.shared.data(from: url),
                   (resp as? HTTPURLResponse)?.statusCode == 200 {
                    self.state = .running
                    return
                }
                try? await Task.sleep(for: .milliseconds(300))
            }
            if self.process != nil {
                self.state = .failed("kimi web 健康检查超时，请查看日志 \(Self.appSupportDir().path)/kimi-web.log")
            }
        }
    }

    static func findKimiBinary() -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = [
            ProcessInfo.processInfo.environment["KIMI_PATH"],
            "\(home)/.local/bin/kimi",
            "/opt/homebrew/bin/kimi",
            "/usr/local/bin/kimi",
        ].compactMap { $0 }
        for c in candidates where FileManager.default.isExecutableFile(atPath: c) {
            return c
        }
        // fallback: ask the login shell
        let p = Process()
        let pipe = Pipe()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = ["-l", "-c", "which kimi"]
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        if let _ = try? p.run() {
            p.waitUntilExit()
            let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !out.isEmpty, FileManager.default.isExecutableFile(atPath: out) { return out }
        }
        return nil
    }

    private static func findFreePort(from start: Int) -> Int? {
        for p in start..<(start + 10) {
            if isPortFree(p) { return p }
        }
        return nil
    }

    private static func isPortFree(_ port: Int) -> Bool {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(port).bigEndian
        addr.sin_addr = in_addr(s_addr: INADDR_ANY)
        let result = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        return result == 0
    }

    static func appSupportDir() -> URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("KimiDesk")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
