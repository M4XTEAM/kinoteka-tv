import Foundation

// ===========================================================
// Клиент бэкенда Кинотеки (Cloudflare worker):
// логин (cookie kt_session), /api/me, /api/sync, /api/players,
// /api/kp, /api/yl-egress, /api/ai.
// Cookie живёт в HTTPCookieStorage.shared → переживает перезапуск.
// ===========================================================

enum Backend {
    static let base = URL(string: "https://kinoteka.pages.dev")!

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    struct Me: Codable {
        let ok: Bool?
        let login: String?
        let expiresAt: Double?
    }

    static var hasSessionCookie: Bool {
        (HTTPCookieStorage.shared.cookies(for: base) ?? []).contains { $0.name == "kt_session" }
    }

    // ---- Вход: POST /__auth/login (form) → 302 + Set-Cookie ----
    static func login(_ login: String, password: String) async -> Bool {
        var req = URLRequest(url: base.appendingPathComponent("__auth/login"))
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        var comp = URLComponents()
        comp.queryItems = [
            URLQueryItem(name: "login", value: login),
            URLQueryItem(name: "p", value: password),
        ]
        req.httpBody = comp.percentEncodedQuery?.data(using: .utf8)
        do {
            _ = try await URLSession.shared.data(for: req)
            // Успех = воркер поставил cookie kt_session (при 401 её нет).
            if hasSessionCookie { return await me() != nil }
            return false
        } catch { return false }
    }

    static func logout() async {
        var req = URLRequest(url: base.appendingPathComponent("__auth/logout"))
        req.httpMethod = "GET"
        _ = try? await URLSession.shared.data(for: req)
        for c in HTTPCookieStorage.shared.cookies(for: base) ?? [] {
            HTTPCookieStorage.shared.deleteCookie(c)
        }
    }

    static func me() async -> Me? {
        do {
            let (data, resp) = try await URLSession.shared.data(from: base.appendingPathComponent("api/me"))
            guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            let m = try decoder.decode(Me.self, from: data)
            return (m.ok == true && m.login != nil) ? m : nil
        } catch { return nil }
    }

    // ---- Синк: POST = upload+merge+download; GET = только download ----
    static func syncPost(_ state: [String: Any]) async -> (state: [String: Any]?, status: Int) {
        var req = URLRequest(url: base.appendingPathComponent("api/sync"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["state": state])
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
            guard status == 200,
                  let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { return (nil, status) }
            return (obj["state"] as? [String: Any], status)
        } catch { return (nil, 0) }
    }

    static func syncGet() async -> [String: Any]? {
        do {
            let (data, resp) = try await URLSession.shared.data(from: base.appendingPathComponent("api/sync"))
            guard let http = resp as? HTTPURLResponse, http.statusCode == 200,
                  let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { return nil }
            return obj["state"] as? [String: Any]
        } catch { return nil }
    }

    // ---- Балансеры: /api/players?imdb=tt…|kp=… ----
    static func players(_ wid: WatchId) async -> [BalancerPlayer] {
        guard let q = wid.query else { return [] }
        do {
            let (data, _) = try await URLSession.shared.data(from: URL(string: "\(base.absoluteString)/api/players?\(q)")!)
            if let arr = try? decoder.decode([BalancerPlayer].self, from: data) { return arr }
            struct Wrap: Codable { let data: [BalancerPlayer]? }
            if let w = try? decoder.decode(Wrap.self, from: data) { return w.data ?? [] }
            return []
        } catch { return [] }
    }

    // ---- Кинопаб: /api/kp ----
    static func kinopub(type: MediaType, wid: WatchId, title: String?, orig: String?,
                        season: Int?, episode: Int?) async -> KpResponse? {
        var comp = URLComponents(url: base.appendingPathComponent("api/kp"), resolvingAgainstBaseURL: false)!
        var items = [URLQueryItem(name: "type", value: type.rawValue)]
        if let imdb = wid.imdb { items.append(.init(name: "imdb", value: imdb)) }
        if let kp = wid.kp { items.append(.init(name: "kp", value: kp)) }
        if let t = title, !t.isEmpty { items.append(.init(name: "title", value: t)) }
        if let o = orig, !o.isEmpty { items.append(.init(name: "orig", value: o)) }
        if type == .tv {
            items.append(.init(name: "season", value: String(season ?? 1)))
            items.append(.init(name: "episode", value: String(episode ?? 1)))
        }
        comp.queryItems = items
        do {
            let (data, _) = try await URLSession.shared.data(from: comp.url!)
            return try decoder.decode(KpResponse.self, from: data)
        } catch { return nil }
    }

    // ---- Телефон-egress (ylitron): база туннеля ----
    private static var cachedEgress: String?
    static func ylEgress() async -> String? {
        if let c = cachedEgress { return c }
        do {
            let (data, resp) = try await URLSession.shared.data(from: base.appendingPathComponent("api/yl-egress"))
            guard let http = resp as? HTTPURLResponse, http.statusCode == 200,
                  let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  var u = obj["url"] as? String, !u.isEmpty
            else { return nil }
            if u.hasSuffix("/") { u.removeLast() }
            cachedEgress = u
            return u
        } catch { return nil }
    }

    // ---- ИИ-ассистент: /api/ai ----
    static func ai(messages: [[String: String]]) async -> AIResponse? {
        var req = URLRequest(url: base.appendingPathComponent("api/ai"))
        req.httpMethod = "POST"
        req.timeoutInterval = 60
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["messages": messages])
        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            return try? JSONDecoder().decode(AIResponse.self, from: data)
        } catch { return nil }
    }
}
