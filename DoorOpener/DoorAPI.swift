import Foundation
import SwiftUI
import Combine

/// 门禁系统 API 客户端（单例）
/// 基于抓包得到的真实接口；会话 Cookie 由 HTTPCookieStorage 自动保持。
@MainActor
final class DoorAPI: ObservableObject {

    static let shared = DoorAPI()

    // MARK: - 配置（按实际服务器修改）
    private let base = "http://10.85.160.4/Access/Standard/Access/"
    private let auth = "http://10.85.160.4/Access/Account/"
    private let user = "gzb1"
    private let passwordMD5 = "21218cca77804d2ba1922c33e0151105" // MD5(888888)
    private let dpCode = "00000000"
    private let systemID = "48"

    // MARK: - 发布状态
    @Published var loginState: LoginState = .idle
    @Published var captchaImage: UIImage?
    @Published var doors: [Door] = []
    @Published var isBusy = false
    @Published var results: [OpResult] = []
    @Published var lastError: String?

    private var cookieStorage = HTTPCookieStorage.shared
    private var keepAliveTask: Task<Void, Never>?
    private let cookieKey = "dooropener_saved_cookies"
    private let userKey = "dooropener_user"

    private init() {
        loadBundledDoors()
        restoreCookies()
        // 启动时先尝试恢复会话：若 Cookie 仍有效则免登录直接进入
        Task { await restoreSession() }
    }

    deinit {
        keepAliveTask?.cancel()
    }

    // MARK: - Cookie 持久化
    /// 把 Cookie 的关键字段存成字典数组（避免 NSSecureCoding 兼容问题）
    private func cookieDict(_ c: HTTPCookie) -> [String: Any] {
        return [
            "name": c.name, "value": c.value,
            "domain": c.domain, "path": c.path,
            "expires": c.expiresDate?.timeIntervalSince1970 ?? 0
        ]
    }

    /// App 启动时把上次保存的 Cookie 恢复到 HTTPCookieStorage
    private func restoreCookies() {
        guard let arr = UserDefaults.standard.array(forKey: cookieKey) as? [[String: Any]],
              let url = URL(string: base) else { return }
        for d in arr {
            guard let name = d["name"] as? String,
                  let value = d["value"] as? String,
                  let domain = d["domain"] as? String,
                  let path = d["path"] as? String else { continue }
            let expires = d["expires"] as? Double ?? 0
            var props: [HTTPCookiePropertyKey: Any] = [
                .name: name, .value: value, .domain: domain, .path: path
            ]
            if expires > 0 { props[.expires] = Date(timeIntervalSince1970: expires) }
            if let c = HTTPCookie(properties: props) {
                cookieStorage.setCookie(c)
            }
        }
        _ = url
    }

    /// 每次登录成功后把 Cookie 存到 UserDefaults（跨 App 重启保留）
    private func persistCookies() {
        guard let cookies = cookieStorage.cookies else { return }
        let relevant = cookies.filter { $0.domain.contains("10.85.160.4") }
        let arr = relevant.map { cookieDict($0) }
        UserDefaults.standard.set(arr, forKey: cookieKey)
    }

    /// 启动时用现有 Cookie 探测会话是否有效，有效则免登录
    func restoreSession() async {
        guard let cookies = cookieStorage.cookies, !cookies.isEmpty else {
            loginState = .needCaptcha
            return
        }
        let valid = await probeSession()
        if valid {
            loginState = .loggedIn
            startKeepAlive()
        } else {
            loginState = .needCaptcha
        }
    }

    /// 用一个轻量请求探测会话是否有效（返回登录页 HTML 则无效）
    private func probeSession() async -> Bool {
        do {
            let raw = try await post(base + "Id_Monitor/GetTermStatusMonitor", params: [
                "AreaId": "", "Systemid": systemID, "ExtendId": "", "ExtendName": "",
                "OnLineStatus": "", "SortColName": "", "sortType": "", "EnableTermType": "0",
                "page": "1", "rows": "1"
            ])
            let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.hasPrefix("[") || t.hasPrefix("{")
        } catch {
            return false
        }
    }

    /// 保活：每 5 分钟发一次轻量请求，维持服务端滑动过期（20 分钟内无请求才失效）
    func startKeepAlive() {
        keepAliveTask?.cancel()
        keepAliveTask = Task { [weak self] in
            while true {
                try? await Task.sleep(nanoseconds: 300_000_000_000) // 5 分钟
                if Task.isCancelled { break }
                guard let self = self, self.loginState == .loggedIn else { break }
                let ok = await self.probeSession()
                if !ok {
                    // 会话已失效，提示重新登录
                    await MainActor.run { self.loginState = .needCaptcha }
                    break
                }
            }
        }
    }

    // MARK: - 内置门牌数据
    private func loadBundledDoors() {
        guard let url = Bundle.main.url(forResource: "doors", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            // 若资源缺失，给出可感知的提示但仍允许在线查询
            self.lastError = "未找到内置门牌数据 doors.json"
            return
        }
        do {
            let list = try JSONDecoder().decode([Door].self, from: data)
            self.doors = list
        } catch {
            self.lastError = "门牌数据解析失败: \(error.localizedDescription)"
        }
    }

    // MARK: - 会话 Cookie 处理
    private func clearCookies() {
        for c in (cookieStorage.cookies ?? []) {
            cookieStorage.deleteCookie(c)
        }
    }

    /// 从响应里收集 Set-Cookie（URLSession 默认已处理，这里兜底）
    private func syncCookies(from response: HTTPURLResponse, url: URL) {
        guard let header = response.allHeaderFields as? [String: String] else { return }
        let cookies = HTTPCookie.cookies(withResponseHeaderFields: header, for: url)
        cookieStorage.setCookies(cookies, for: url, mainDocumentURL: nil)
    }

    // MARK: - 通用请求
    private func post(_ urlString: String, params: [String: String]) async throws -> String {
        guard let url = URL(string: urlString) else { throw APIError.badURL }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        req.httpBody = params.map { key, value in
            let k = key.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? key
            let v = value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? value
            return "\(k)=\(v)"
        }.joined(separator: "&").data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: req)
        if let http = response as? HTTPURLResponse {
            syncCookies(from: http, url: url)
        }
        return String(data: data, encoding: .utf8) ?? ""
    }

    private func get(_ urlString: String) async throws -> (Data, HTTPURLResponse?) {
        guard let url = URL(string: urlString) else { throw APIError.badURL }
        let (data, response) = try await URLSession.shared.data(for: URLRequest(url: url))
        if let http = response as? HTTPURLResponse {
            syncCookies(from: http, url: url)
        }
        return (data, response as? HTTPURLResponse)
    }

    /// 退出登录：清除内存与持久化的会话
    func logout() {
        keepAliveTask?.cancel()
        keepAliveTask = nil
        clearCookies()
        UserDefaults.standard.removeObject(forKey: cookieKey)
        loginState = .idle
        captchaImage = nil
        results.removeAll()
    }

    // MARK: - 验证码
    func fetchCaptcha() async {
        loginState = .needCaptcha
        captchaImage = nil
        do {
            let (data, _) = try await get(auth + "ValideCode")
            captchaImage = UIImage(data: data)
        } catch {
            loginState = .failed("验证码获取失败: \(error.localizedDescription)")
        }
    }

    // MARK: - 登录
    func login(code: String) async {
        isBusy = true
        defer { isBusy = false }
        do {
            let raw = try await post(auth + "Login", params: [
                "dpCode": dpCode,
                "userName": user,
                "password": passwordMD5,
                "validCode": code
            ])
            let result = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if result == "1" {
                loginState = .loggedIn
                persistCookies()   // 保存会话，下次启动可免登录
                startKeepAlive()   // 启动保活
            } else {
                loginState = .failed(result.isEmpty ? "登录失败" : result)
                // 验证码大概率过期，重新取一张
                await fetchCaptcha()
            }
        } catch {
            loginState = .failed("登录请求失败: \(error.localizedDescription)")
        }
    }

    // MARK: - 门牌搜索（基于内置数据，本地即时匹配）
    func searchDoors(keyword: String) -> [Door] {
        let k = keyword.trimmingCharacters(in: .whitespaces)
        if k.isEmpty { return [] }
        let direct = doors.filter { $0.name.localizedCaseInsensitiveContains(k) }
        if !direct.isEmpty { return direct }
        let nk = normalize(k)
        return doors.filter { !nk.isEmpty && normalize($0.name).contains(nk) }
    }

    private func normalize(_ s: String) -> String {
        var t = s
        for word in ["房间", "前门", "后门", "电梯", "办公室", "宿舍", "楼", "室", "门", "层", "号"] {
            t = t.replacingOccurrences(of: word, with: "")
        }
        return t.replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: " ", with: "")
    }

    // MARK: - 开门（单个/批量）
    func openDoors(_ targets: [Door]) async {
        guard !targets.isEmpty else { return }
        isBusy = true
        defer { isBusy = false }

        // 逐个下发（接口不支持逗号批量）。请求本身很快，顺序执行即可。
        for door in targets {
            do {
                let raw = try await post(base + "Id_Monitor/SendCommand", params: [
                    "Id": "\(door.id)",
                    "OpenType": "338",
                    "Delaytime": "5",
                    "Systemid": systemID
                ])
                // 会话过期时返回 HTML，JSON 解析会失败
                let ok = raw.contains("\"State\":true") || raw.contains("\"State\": true")
                let msg = extractJSONString(raw, key: "Message") ?? (ok ? "命令发送成功" : "命令发送失败")
                if ok {
                    let final = await waitResult(ext: door.ext)
                    let result = OpResult(
                        doorName: door.name,
                        success: final?.isSuccess ?? false,
                        message: final?.refMsg?.trimmingCharacters(in: .whitespaces) ?? msg,
                        time: final?.commandRecvDt ?? Self.nowString()
                    )
                    results.insert(result, at: 0)
                } else {
                    let result = OpResult(doorName: door.name, success: false, message: msg, time: Self.nowString())
                    results.insert(result, at: 0)
                    if rawLooksLikeLogin(msg) { loginState = .needCaptcha }
                }
            } catch {
                let result = OpResult(doorName: door.name, success: false, message: error.localizedDescription, time: Self.nowString())
                results.insert(result, at: 0)
            }
        }
    }

    /// 轮询命令结果直到出现终态（0.2s 间隔，最长 3s）
    private func waitResult(ext: Int) async -> CommandResult? {
        for _ in 0..<15 {
            if let list = await queryCommands(ext: ext), let first = list.first {
                let msg = first.refMsg?.trimmingCharacters(in: .whitespaces) ?? ""
                if !msg.contains("生成") { return first }
            }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        return nil
    }

    private func queryCommands(ext: Int) async -> [CommandResult]? {
        do {
            let raw = try await post(base + "Id_Monitor/GetCommandListMonitor", params: [
                "ver": "0", "Systemid": systemID, "Count": "3", "ExtendId": "\(ext)"
            ])
            guard let data = raw.data(using: .utf8) else { return nil }
            return try JSONDecoder().decode([CommandResult].self, from: data)
        } catch {
            return nil
        }
    }

    /// 手动刷新在线设备状态（可选功能）
    func refreshOnlineStatus() async {
        do {
            let raw = try await post(base + "Id_Monitor/GetTermStatusMonitor", params: [
                "AreaId": "", "Systemid": systemID, "ExtendId": "", "ExtendName": "",
                "OnLineStatus": "", "SortColName": "", "sortType": "", "EnableTermType": "0",
                "page": "1", "rows": "2000"
            ])
            guard let data = raw.data(using: .utf8) else { return }
            struct Row: Codable {
                let ID: Double
                let EXTENDID: Double
                let EXTENDNAME: String
                let FULLNAME: String?
                let ISONLINE: Double
            }
            let rows = try JSONDecoder().decode([Row].self, from: data)
            var map: [Int: Bool] = [:]
            for r in rows { map[Int(r.ID)] = r.ISONLINE == 1 }
            self.doors = self.doors.map { d in
                var copy = d
                if let online = map[d.id] { copy = Door(id: d.id, ext: d.ext, name: d.name, full: d.full, online: online) }
                return copy
            }
        } catch {
            self.lastError = "刷新状态失败: \(error.localizedDescription)"
        }
    }

    // MARK: - 工具
    private func extractJSONString(_ raw: String, key: String) -> String? {
        guard let data = raw.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let value = obj[key] as? String else { return nil }
        return value
    }

    private func rawLooksLikeLogin(_ msg: String) -> Bool {
        msg.contains("登录") || msg.contains("DOCTYPE")
    }

    private static func nowString() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f.string(from: Date())
    }
}

enum APIError: Error {
    case badURL
}
