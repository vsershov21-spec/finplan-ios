import Foundation
import WebKit
import CryptoKit

/// Интерфейс Финплана живёт в самом приложении, а не грузится с сайта при каждом запуске.
/// Файлы (index.html, app.js, app.css, картинки) лежат в Application Support/ui и показываются по адресу finplan-app://app/.
/// Обновление — в фоне: сравниваем список файлов сервера (ui_manifest) с тем, что лежит, и докачиваем только изменённое.
/// Запросы к api.php идут через URLSession приложения (свои cookie, повторы, таймауты), а не через WebView.
enum LocalUI {
    static let scheme = "finplan-app"
    static let start = URL(string: "\(scheme)://app/index.html")!
    private static let fm = FileManager.default
    static var root: URL {
        let d = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("ui", isDirectory: true)
        try? fm.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }
    static var current: URL? {
        guard let v = UserDefaults.standard.string(forKey: "uiVersion") else { return nil }
        let d = root.appendingPathComponent(v, isDirectory: true)
        return fm.fileExists(atPath: d.appendingPathComponent("index.html").path) ? d : nil
    }
    static var isReady: Bool { current != nil }
    static var version: String? { UserDefaults.standard.string(forKey: "uiVersion") }
    /// новая версия скачана и ждёт, когда приложение спокойно перезагрузит страницу
    static var pending: String? {
        get { UserDefaults.standard.string(forKey: "uiPending") }
        set { UserDefaults.standard.set(newValue, forKey: "uiPending") }
    }

    static let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.httpCookieStorage = .shared
        c.httpShouldSetCookies = true
        c.httpCookieAcceptPolicy = .always
        c.timeoutIntervalForRequest = 25
        c.timeoutIntervalForResource = 120
        c.waitsForConnectivity = false
        c.requestCachePolicy = .reloadIgnoringLocalCacheData
        c.httpAdditionalHeaders = ["User-Agent": "FinplanApp/\(WebViewController.appVersion) iOS"]
        return URLSession(configuration: c)
    }()

    private struct Manifest: Decodable { let ver: String; let files: [String: String] }
    private static var syncing = false

    /// Скачать новую версию интерфейса, если она есть. done(true) — версия сменилась.
    static func sync(_ done: @escaping (Bool) -> Void) {
        if syncing { return done(false) }
        syncing = true
        var req = URLRequest(url: WebViewController.base.appendingPathComponent("api.php"))
        req.url = URL(string: req.url!.absoluteString + "?a=ui_manifest")
        session.dataTask(with: req) { data, resp, _ in
            defer { syncing = false }
            guard (resp as? HTTPURLResponse)?.statusCode == 200, let data, let m = try? JSONDecoder().decode(Manifest.self, from: data),
                  !m.ver.isEmpty, m.ver.range(of: "^[A-Za-z0-9]+$", options: .regularExpression) != nil else { return DispatchQueue.main.async { done(false) } }
            if m.ver == version || m.ver == pending { return DispatchQueue.main.async { done(false) } }
            let dir = root.appendingPathComponent(m.ver, isDirectory: true), tmp = root.appendingPathComponent(".tmp-\(m.ver)", isDirectory: true)
            try? fm.removeItem(at: tmp); try? fm.createDirectory(at: tmp, withIntermediateDirectories: true)
            let old = current
            let group = DispatchGroup(); var ok = true; let lockQ = DispatchQueue(label: "ui.sync")
            for (path, sha) in m.files {
                guard !path.contains(".."), !path.hasPrefix("/") else { ok = false; continue }
                let dst = tmp.appendingPathComponent(path)
                try? fm.createDirectory(at: dst.deletingLastPathComponent(), withIntermediateDirectories: true)
                if let o = old?.appendingPathComponent(path), let d = try? Data(contentsOf: o), sha1(d) == sha { try? d.write(to: dst); continue }
                group.enter()
                session.dataTask(with: WebViewController.base.appendingPathComponent(path)) { d, r, _ in
                    defer { group.leave() }
                    guard (r as? HTTPURLResponse)?.statusCode == 200, let d, sha1(d) == sha else { lockQ.sync { ok = false }; return }
                    try? d.write(to: dst)
                }.resume()
            }
            group.notify(queue: .main) {
                guard ok, fm.fileExists(atPath: tmp.appendingPathComponent("index.html").path) else { try? fm.removeItem(at: tmp); return done(false) }
                try? fm.removeItem(at: dir); try? fm.moveItem(at: tmp, to: dir)
                if current == nil { UserDefaults.standard.set(m.ver, forKey: "uiVersion"); cleanup(); done(true) }
                else { pending = m.ver; done(true) }
            }
        }.resume()
    }

    /// переключиться на скачанную версию (страница перезагрузится)
    static func applyPending() -> Bool {
        guard let p = pending, fm.fileExists(atPath: root.appendingPathComponent(p).appendingPathComponent("index.html").path) else { pending = nil; return false }
        UserDefaults.standard.set(p, forKey: "uiVersion"); pending = nil; cleanup(); return true
    }

    private static func cleanup() {
        let keep: Set<String> = [version ?? "", pending ?? ""]
        for d in (try? fm.contentsOfDirectory(atPath: root.path)) ?? [] where !keep.contains(d) { try? fm.removeItem(at: root.appendingPathComponent(d)) }
    }

    static func sha1(_ d: Data) -> String { Insecure.SHA1.hash(data: d).map { String(format: "%02x", $0) }.joined() }

    static func mime(_ ext: String) -> String {
        switch ext.lowercased() {
        case "html": return "text/html; charset=utf-8"
        case "js": return "text/javascript; charset=utf-8"
        case "css": return "text/css; charset=utf-8"
        case "json", "webmanifest": return "application/json"
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "svg": return "image/svg+xml"
        case "woff2": return "font/woff2"
        default: return "application/octet-stream"
        }
    }
}

/// finplan-app://app/… → файл интерфейса из приложения; finplan-app://app/api.php?… (картинки, выгрузки) → сервер через URLSession.
final class LocalUIScheme: NSObject, WKURLSchemeHandler {
    private var live = Set<ObjectIdentifier>()
    private let q = DispatchQueue(label: "ui.scheme")

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        let id = ObjectIdentifier(task); q.sync { _ = live.insert(id) }
        guard let url = task.request.url else { return fail(task, id) }
        var path = url.path; if path.hasPrefix("/") { path.removeFirst() }
        if path.isEmpty { path = "index.html" }
        if path.hasSuffix(".php") {
            var comps = URLComponents(url: WebViewController.base.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
            comps.percentEncodedQuery = url.query
            var req = URLRequest(url: comps.url!); req.httpMethod = task.request.httpMethod ?? "GET"; req.httpBody = task.request.httpBody
            for (k, v) in task.request.allHTTPHeaderFields ?? [:] where !["host", "origin", "cookie"].contains(k.lowercased()) { req.setValue(v, forHTTPHeaderField: k) }
            LocalUI.session.dataTask(with: req) { [weak self] d, r, e in
                guard let self else { return }
                guard let http = r as? HTTPURLResponse, let d else { return self.fail(task, id, e) }
                var h: [String: String] = [:]
                for (k, v) in http.allHeaderFields { if let k = k as? String, let v = v as? String, !["set-cookie", "content-encoding", "content-length", "transfer-encoding"].contains(k.lowercased()) { h[k] = v } }
                h["Content-Length"] = String(d.count)
                self.finish(task, id, HTTPURLResponse(url: url, statusCode: http.statusCode, httpVersion: "HTTP/1.1", headerFields: h)!, d)
            }.resume()
            return
        }
        guard !path.contains(".."), let dir = LocalUI.current, let d = try? Data(contentsOf: dir.appendingPathComponent(path)) else {
            return finish(task, id, HTTPURLResponse(url: url, statusCode: 404, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "text/plain"])!, Data("нет файла".utf8))
        }
        let ext = (path as NSString).pathExtension
        finish(task, id, HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": LocalUI.mime(ext), "Content-Length": String(d.count), "Cache-Control": "no-cache"])!, d)
    }

    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) { q.sync { _ = live.remove(ObjectIdentifier(task)) } }

    private func alive(_ id: ObjectIdentifier) -> Bool { q.sync { live.contains(id) } }
    private func finish(_ task: WKURLSchemeTask, _ id: ObjectIdentifier, _ r: URLResponse, _ d: Data) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.alive(id) else { return }
            task.didReceive(r); task.didReceive(d); task.didFinish()
            self.q.sync { _ = self.live.remove(id) }
        }
    }
    private func fail(_ task: WKURLSchemeTask, _ id: ObjectIdentifier, _ e: Error? = nil) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.alive(id) else { return }
            task.didFailWithError(e ?? URLError(.badServerResponse))
            self.q.sync { _ = self.live.remove(id) }
        }
    }
}

/// fetch("api.php?…") из страницы → сюда (WKScriptMessageHandlerWithReply). Тело — JSON-строка или поля формы с файлами в base64.
final class ApiBridge: NSObject, WKScriptMessageHandlerWithReply {
    func userContentController(_ uc: WKUserContentController, didReceive message: WKScriptMessage, replyHandler: @escaping (Any?, String?) -> Void) {
        guard let b = message.body as? [String: Any], var rel = b["url"] as? String else { return replyHandler(nil, "bad request") }
        if let r = rel.range(of: "api.php") { rel = String(rel[r.lowerBound...]) } else if let r = rel.range(of: #"[a-z]+\.php"#, options: .regularExpression) { rel = String(rel[r.lowerBound...]) }
        guard let url = URL(string: rel, relativeTo: WebViewController.base)?.absoluteURL, url.host == WebViewController.base.host else { return replyHandler(nil, "bad url") }
        var req = URLRequest(url: url); req.httpMethod = (b["method"] as? String ?? "GET").uppercased()
        for (k, v) in (b["headers"] as? [String: String]) ?? [:] { req.setValue(v, forHTTPHeaderField: k) }
        if let form = b["form"] as? [[String: Any]] {
            let bd = "fin-\(UUID().uuidString)"; var body = Data()
            for f in form {
                guard let k = f["k"] as? String else { continue }
                body.append(Data("--\(bd)\r\n".utf8))
                if let b64 = f["file"] as? String, let fd = Data(base64Encoded: b64) {
                    let name = (f["name"] as? String ?? "file").replacingOccurrences(of: "\"", with: "")
                    body.append(Data("Content-Disposition: form-data; name=\"\(k)\"; filename=\"\(name)\"\r\nContent-Type: \(f["type"] as? String ?? "application/octet-stream")\r\n\r\n".utf8)); body.append(fd)
                } else { body.append(Data("Content-Disposition: form-data; name=\"\(k)\"\r\n\r\n\(f["v"] as? String ?? "")".utf8)) }
                body.append(Data("\r\n".utf8))
            }
            body.append(Data("--\(bd)--\r\n".utf8)); req.httpBody = body
            req.setValue("multipart/form-data; boundary=\(bd)", forHTTPHeaderField: "Content-Type")
        } else if let s = b["body"] as? String { req.httpBody = Data(s.utf8) }
        LocalUI.session.dataTask(with: req) { d, r, e in
            DispatchQueue.main.async {
                guard let http = r as? HTTPURLResponse else { return replyHandler(nil, (e as NSError?)?.localizedDescription ?? "Нет связи с сервером") }
                var h: [String: String] = [:]
                for (k, v) in http.allHeaderFields { if let k = k as? String, let v = v as? String, !["set-cookie", "content-encoding", "content-length", "transfer-encoding"].contains(k.lowercased()) { h[k] = v } }
                replyHandler(["status": http.statusCode, "headers": h, "body": String(data: d ?? Data(), encoding: .utf8) ?? ""], nil)
            }
        }.resume()
    }

    /// Подмена fetch в странице: только для своих .php, всё остальное идёт как обычно.
    static let script = #"""
    (() => {
      if (location.protocol !== "finplan-app:") return;
      window.finAppLocal = true;
      const of = window.fetch.bind(window);
      const b64 = (blob) => new Promise((ok, no) => { const r = new FileReader(); r.onload = () => ok(String(r.result).split(",")[1] || ""); r.onerror = no; r.readAsDataURL(blob); });
      window.fetch = async (input, init) => {
        init = init || {};
        const url = typeof input === "string" ? input : input instanceof URL ? input.href : input.url;
        const rel = String(url).replace(/^finplan-app:\/\/app\//, "");
        if (!/^\/?[a-z]+\.php/.test(rel)) return of(input, init);
        const h = {}; const hh = init.headers instanceof Headers ? Object.fromEntries(init.headers.entries()) : (init.headers || {}); for (const k in hh) h[k] = String(hh[k]);
        const req = { url: rel, method: init.method || "GET", headers: h };
        if (init.body instanceof FormData) { req.form = []; for (const [k, v] of init.body.entries()) req.form.push(v instanceof Blob ? { k, file: await b64(v), name: v.name || "file", type: v.type || "application/octet-stream" } : { k, v: String(v) }); }
        else if (init.body != null) req.body = String(init.body);
        let r;
        try { r = await window.webkit.messageHandlers.finApi.postMessage(req); } catch (e) { throw new TypeError(String(e && e.message || e || "Нет связи")); }
        return new Response(r.body, { status: r.status, headers: r.headers });
      };
    })();
    """#
}
