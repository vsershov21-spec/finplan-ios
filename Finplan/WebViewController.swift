import UIKit
import WebKit
import ObjectiveC
import WidgetKit
import UserNotifications

/// Экран приложения: сайт Финплана во весь экран + мост к возможностям iPhone.
final class WebViewController: UIViewController, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler, WKDownloadDelegate {
    static let base: URL = URL(string: (Bundle.main.object(forInfoDictionaryKey: "FinBaseURL") as? String) ?? "https://fin.vershov.com/")!
    static var appVersion: String { (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "1.0" }

    private(set) var webView: WKWebView!
    /// куда перейти, когда сайт загрузится (из пуша, виджета или ссылки finplan://)
    var pendingTarget: String?
    private var pageReady = false
    private var loggedIn = false
    private var lastSnap: FinSnapshot?
    private let lock = LockView()
    private let offline = OfflineView()
    private let splash = SplashView()
    private var backgroundAt: Date?
    private var downloads: [WKDownload: URL] = [:]
    private var autoLoginTried = false

    // MARK: - экран

    override func loadView() {
        let cfg = WKWebViewConfiguration()
        cfg.websiteDataStore = .default()
        cfg.allowsInlineMediaPlayback = true
        cfg.applicationNameForUserAgent = "FinplanApp/\(Self.appVersion) Mobile/15E148 Safari/604.1"
        let uc = WKUserContentController()
        uc.add(WeakMessageHandler(self), name: "fin")
        uc.addUserScript(WKUserScript(source: Self.infoScript(), injectionTime: .atDocumentStart, forMainFrameOnly: true))
        cfg.userContentController = uc

        let wv = WKWebView(frame: .zero, configuration: cfg)
        wv.navigationDelegate = self
        wv.uiDelegate = self
        wv.isOpaque = false
        wv.backgroundColor = UIColor(named: "Paper")
        wv.scrollView.backgroundColor = UIColor(named: "Paper")
        wv.scrollView.contentInsetAdjustmentBehavior = .never
        // Страница целиком никогда не прокручивается: вся прокрутка внутри приложения (списки, шторки).
        // Иначе iOS при появлении клавиатуры сдвигает весь экран вверх и интерфейс «прыгает».
        wv.scrollView.isScrollEnabled = false
        wv.scrollView.bounces = false
        wv.scrollView.delegate = PageLock.shared
        wv.allowsBackForwardNavigationGestures = false
        wv.allowsLinkPreview = false
        if #available(iOS 16.4, *) {
            #if DEBUG
            wv.isInspectable = true
            #endif
        }
        wv.hideInputAccessoryBar() // без серой полоски «˄ ˅ Готово» над клавиатурой, как в мессенджерах
        webView = wv
        view = wv
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        offline.onRetry = { [weak self] in self?.reload() }
        lock.onUnlock = { [weak self] in self?.unlocked() }
        NotificationCenter.default.addObserver(self, selector: #selector(didEnterBackground), name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(willEnterForeground), name: UIApplication.willEnterForegroundNotification, object: nil)
        splash.show(in: view)
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in self?.splash.hide() } // на всякий случай: заставка не висит вечно
        if Settings.lockOn && Keychain.hasCredentials { lock.show(in: view) }
        reload()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if lock.isShown { lock.authenticate() }
    }

    override var preferredStatusBarStyle: UIStatusBarStyle { .default }

    private func reload() {
        offline.hide()
        var url = Self.base
        if let t = pendingTarget, ["home", "ops", "forecast", "money", "plan", "more"].contains(t) {
            url = URL(string: "#\(t)", relativeTo: Self.base)!.absoluteURL
        }
        webView.load(URLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 20))
    }

    private static func infoScript() -> String {
        var info: [String: Any] = ["platform": "ios", "version": appVersion, "faceid": Settings.lockOn, "faceidAsked": Settings.lockAsked, "biometry": Biometry.name]
        info["push"] = "unknown"
        info["sms"] = SMSKey.token != nil
        info["intents"] = true
        #if targetEnvironment(macCatalyst)
        info["mac"] = true
        #endif
        let data = (try? JSONSerialization.data(withJSONObject: info)) ?? Data("{}".utf8)
        return "window.finNativeInfo=\(String(data: data, encoding: .utf8) ?? "{}");"
    }

    // MARK: - блокировка

    @objc private func didEnterBackground() {
        backgroundAt = Date()
        // прячем суммы в переключателе приложений
        if Settings.lockOn && loggedIn && !lock.isShown { lock.show(in: view, coverOnly: true) }
    }

    @objc private func willEnterForeground() {
        let away = backgroundAt.map { Date().timeIntervalSince($0) } ?? 0
        backgroundAt = nil
        if Settings.lockOn && loggedIn && away > 60 {
            lock.show(in: view)
            lock.authenticate()
        } else {
            lock.hide()
        }
        resumeSync()
        sendPushState()
    }

    private func unlocked() { resumeSync() }

    func resumeSync() { js("window.finNativeResume && window.finNativeResume()") }

    // MARK: - переходы из пуша, виджета, finplan://

    static func target(fromDeepLink url: URL) -> String {
        // finplan://plan, finplan://notif
        let h = url.host ?? url.path.replacingOccurrences(of: "/", with: "")
        return h.isEmpty ? "home" : h
    }

    static func target(fromPath path: String) -> String {
        if let i = path.firstIndex(of: "#") { return String(path[path.index(after: i)...]) }
        return "notif"
    }

    func open(target: String) {
        if pageReady && loggedIn {
            js("window.finNativeOpen && window.finNativeOpen(\(Self.jsString(target)))")
        } else {
            pendingTarget = target
        }
    }

    // MARK: - мост JS → iPhone

    func userContentController(_ uc: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
        switch type {
        case "haptic":
            Haptics.play(body["style"] as? String ?? "light")
        case "badge":
            let n = (body["n"] as? NSNumber)?.intValue ?? 0
            UNUserNotificationCenter.current().setBadgeCount(max(0, n)) { _ in }
        case "widget":
            guard let raw = body["snap"], let data = try? JSONSerialization.data(withJSONObject: raw),
                  let snap = try? JSONDecoder().decode(FinSnapshot.self, from: data) else { return }
            var cmp = snap; cmp.updated = lastSnap?.updated ?? 0
            if cmp != lastSnap || lastSnap == nil || snap.updated - (lastSnap?.updated ?? 0) > 900 {
                lastSnap = snap
                SharedStore.save(snap)
                WidgetCenter.shared.reloadAllTimelines()
            }
        case "ready":
            loggedIn = true
            splash.hide()
            if let t = pendingTarget {
                pendingTarget = nil
                if !["home", "ops", "forecast", "money", "plan", "more"].contains(t) { open(target: t) }
            }
            sendPushState()
        case "pushAsk":
            askPush()
        case "cred":
            if let l = body["login"] as? String, let p = body["password"] as? String { Keychain.save(login: l, password: p) }
            loggedIn = true
        case "credBad":
            Keychain.clear()
        case "loginShown":
            splash.hide()
            loggedIn = false
            lock.hide()
            autoLogin()
        case "logout":
            loggedIn = false
            Keychain.clear()
            SharedStore.clear()
            lastSnap = nil
            WidgetCenter.shared.reloadAllTimelines()
            UNUserNotificationCenter.current().setBadgeCount(0) { _ in }
        case "faceid":
            let on = (body["on"] as? Bool) ?? true
            Settings.lockAsked = true
            if on {
                // включаем, только если владелец телефона подтвердит
                Biometry.authenticate(reason: "Включить вход по \(Biometry.name)") { ok in Settings.lockOn = ok; if !ok { self.js("window.finNativeInfo&&(finNativeInfo.faceid=false)") } }
            } else {
                Settings.lockOn = false
            }
        case "open":
            if let s = body["url"] as? String, let u = URL(string: s) { UIApplication.shared.open(u) }
        case "smsToken":
            SMSKey.token = body["token"] as? String
            js("window.finNativeInfo&&(finNativeInfo.sms=true)")
        default:
            break
        }
    }

    /// вход по Face ID: пароль лежит в связке ключей, подставляем его в форму входа
    private func autoLogin() {
        guard !autoLoginTried, let cred = Keychain.load() else { return }
        autoLoginTried = true
        Biometry.authenticate(reason: "Войти в Финплан") { [weak self] ok in
            guard ok, let self else { return }
            self.js("window.finNativeLogin && window.finNativeLogin(\(Self.jsString(cred.login)), \(Self.jsString(cred.password)))")
        }
    }

    private func askPush() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
            DispatchQueue.main.async {
                if granted { UIApplication.shared.registerForRemoteNotifications() }
                self.sendPushState(perm: granted ? "granted" : "denied", force: !granted)
            }
        }
    }

    /// сообщаем сайту, разрешены ли пуши, и токен устройства — сайт сохранит его на сервере
    func sendPushState(perm: String? = nil, force: Bool = false) {
        guard pageReady else { return }
        UNUserNotificationCenter.current().getNotificationSettings { s in
            let p: String = perm ?? {
                switch s.authorizationStatus {
                case .authorized, .provisional, .ephemeral: return "granted"
                case .denied: return "denied"
                default: return "default"
                }
            }()
            DispatchQueue.main.async {
                let token = Push.token ?? ""
                if token.isEmpty && !force && p == "granted" { return } // токен ещё не пришёл — дождёмся didRegister
                self.js("window.finNativePush && window.finNativePush(\(Self.jsString(token)), \(Self.jsString(Push.env)), \(Self.jsString(p)))")
            }
        }
    }

    // MARK: - навигация

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = action.request.url else { return decisionHandler(.cancel) }
        if action.shouldPerformDownload { return decisionHandler(.download) }
        let scheme = url.scheme?.lowercased() ?? ""
        if scheme == "about" || scheme == "blob" || scheme == "data" { return decisionHandler(.allow) }
        if (scheme == "https" || scheme == "http") && url.host == Self.base.host {
            if url.query?.contains("a=export") == true { return decisionHandler(.download) }
            return decisionHandler(.allow)
        }
        // чужие сайты, Telegram, календарь (webcal), Напоминания, почта — открываем снаружи
        if action.targetFrame?.isMainFrame == false && (scheme == "https" || scheme == "http") { return decisionHandler(.allow) }
        UIApplication.shared.open(url)
        decisionHandler(.cancel)
    }

    func webView(_ webView: WKWebView, decidePolicyFor response: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        if let r = response.response as? HTTPURLResponse,
           let cd = r.value(forHTTPHeaderField: "Content-Disposition"), cd.lowercased().contains("attachment") {
            return decisionHandler(.download)
        }
        decisionHandler(response.canShowMIMEType ? .allow : .download)
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) { download.delegate = self }
    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) { download.delegate = self }

    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(suggestedFilename.isEmpty ? "finplan.json" : suggestedFilename)
        downloads[download] = url
        completionHandler(url)
    }

    func downloadDidFinish(_ download: WKDownload) {
        guard let url = downloads.removeValue(forKey: download) else { return }
        let vc = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        vc.popoverPresentationController?.sourceView = view
        present(vc, animated: true)
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        downloads.removeValue(forKey: download)
    }

    // ссылки target=_blank
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = action.request.url {
            if url.host == Self.base.host { webView.load(action.request) } else { UIApplication.shared.open(url) }
        }
        return nil
    }

    // window.alert / confirm — нативными окнами
    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        let a = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler() })
        present(a, animated: true)
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        let a = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "Отмена", style: .cancel) { _ in completionHandler(false) })
        a.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler(true) })
        present(a, animated: true)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        pageReady = true
        offline.hide()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        let e = error as NSError
        if e.code == NSURLErrorCancelled || e.code == 102 { return } // 102 — переход отдан загрузке
        pageReady = false
        splash.hide()
        offline.show(in: view, message: e.localizedDescription)
    }

    // процесс страницы выгрузили из памяти — перезагружаем
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { reload() }

    // MARK: - мелочи

    private func js(_ code: String) {
        guard pageReady else { return }
        webView.evaluateJavaScript(code, completionHandler: nil)
    }

    static func jsString(_ s: String) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: [s])) ?? Data("[\"\"]".utf8)
        let arr = String(data: data, encoding: .utf8) ?? "[\"\"]"
        return String(arr.dropFirst().dropLast())
    }
}

/// WKUserContentController держит обработчик сильной ссылкой — разрываем цикл.
final class WeakMessageHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?
    init(_ t: WKScriptMessageHandler) { target = t }
    func userContentController(_ uc: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(uc, didReceive: message)
    }
}

enum Settings {
    static var lockOn: Bool {
        get { UserDefaults.standard.object(forKey: "lockOn") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "lockOn") }
    }
    /// человек уже ответил на «Входить по Face ID?» после первого входа
    static var lockAsked: Bool {
        get { UserDefaults.standard.bool(forKey: "lockAsked") }
        set { UserDefaults.standard.set(newValue, forKey: "lockAsked") }
    }
}

/// Убираем панель над клавиатурой (стрелки и «Готово»): подменяем класс содержимого WKWebView на наследника без inputAccessoryView.
private final class NoAccessoryHelper: NSObject { @objc var inputAccessoryView: UIView? { nil } }
extension WKWebView {
    func hideInputAccessoryBar() {
        guard let target = scrollView.subviews.first(where: { String(describing: type(of: $0)).hasPrefix("WKContent") }),
              let base: AnyClass = object_getClass(target) else { return }
        let name = "\(base)_FinNoAccessory"
        var cls: AnyClass? = NSClassFromString(name)
        if cls == nil, let c = objc_allocateClassPair(base, name, 0) {
            if let m = class_getInstanceMethod(NoAccessoryHelper.self, #selector(getter: NoAccessoryHelper.inputAccessoryView)) {
                class_addMethod(c, #selector(getter: UIResponder.inputAccessoryView), method_getImplementation(m), method_getTypeEncoding(m))
            }
            objc_registerClassPair(c); cls = c
        }
        if let cls { object_setClass(target, cls) }
    }
}

enum Haptics {
    static func play(_ style: String) {
        switch style {
        case "success": UINotificationFeedbackGenerator().notificationOccurred(.success)
        case "warning": UINotificationFeedbackGenerator().notificationOccurred(.warning)
        case "error": UINotificationFeedbackGenerator().notificationOccurred(.error)
        case "selection": UISelectionFeedbackGenerator().selectionChanged()
        case "medium": UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        case "rigid": UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        default: UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }
}

/// Держит документ на месте: если iOS попробует сдвинуть страницу под клавиатуру, возвращаем её без анимации.
final class PageLock: NSObject, UIScrollViewDelegate {
    static let shared = PageLock()
    func scrollViewDidScroll(_ sv: UIScrollView) { if sv.contentOffset != .zero { sv.contentOffset = .zero } }
    func viewForZooming(in scrollView: UIScrollView) -> UIView? { nil }
}
