import UIKit
import UserNotifications

@main
final class AppDelegate: UIResponder, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    var window: UIWindow?
    let web = WebViewController()

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        if let n = launchOptions?[.remoteNotification] as? [AnyHashable: Any], let u = n["url"] as? String {
            web.pendingTarget = WebViewController.target(fromPath: u)
        }
        if let u = launchOptions?[.url] as? URL { web.pendingTarget = WebViewController.target(fromDeepLink: u) }
        if let sc = launchOptions?[.shortcutItem] as? UIApplicationShortcutItem { web.pendingTarget = sc.type }
        QuickActions.install()
        let w = UIWindow(frame: UIScreen.main.bounds)
        w.backgroundColor = UIColor(named: "Paper")
        w.rootViewController = web
        w.makeKeyAndVisible()
        window = w
        #if targetEnvironment(macCatalyst)
        MacWindow.setup(w)
        #endif
        // если пуши уже разрешены — обновим токен (Apple может его сменить)
        UNUserNotificationCenter.current().getNotificationSettings { s in
            if s.authorizationStatus == .authorized || s.authorizationStatus == .provisional {
                DispatchQueue.main.async { application.registerForRemoteNotifications() }
            }
        }
        return true
    }

    // долгое нажатие на значок приложения: «Трата», «Доход», «Что впереди», «Из банка»
    func application(_ application: UIApplication, performActionFor shortcutItem: UIApplicationShortcutItem, completionHandler: @escaping (Bool) -> Void) {
        web.open(target: shortcutItem.type); completionHandler(true)
    }

    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        web.open(target: WebViewController.target(fromDeepLink: url))
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Push.token = deviceToken.map { String(format: "%02x", $0) }.joined()
        web.sendPushState()
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        Push.lastError = error.localizedDescription
        web.sendPushState(force: true)
    }

    // пуш пришёл, пока приложение открыто — показываем баннер
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
        DispatchQueue.main.async { self.web.resumeSync() }
    }

    // нажали на пуш — открываем нужный раздел
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let path = response.notification.request.content.userInfo["url"] as? String ?? "./#notif"
        DispatchQueue.main.async { self.web.open(target: WebViewController.target(fromPath: path)) }
        completionHandler()
    }
}

enum Push {
    static var token: String?
    static var lastError: String?
    #if DEBUG
    static let env = "sandbox"
    #else
    static let env = "prod"
    #endif
}

/// Быстрые действия на значке приложения (долгое нажатие на домашнем экране).
enum QuickActions {
    static func install() {
        let item = { (type: String, title: String, sub: String?, sym: String) in
            UIApplicationShortcutItem(type: type, localizedTitle: title, localizedSubtitle: sub, icon: UIApplicationShortcutIcon(systemImageName: sym), userInfo: nil) }
        UIApplication.shared.shortcutItems = [
            item("spend", "Трата", "записать за пару касаний", "minus.circle"),
            item("income", "Доход", nil, "plus.circle"),
            item("agenda", "Что впереди", "платежи и поступления", "calendar"),
            item("bank", "Из банка", "подборка из СМС", "tray.and.arrow.down")
        ]
    }
}

#if targetEnvironment(macCatalyst)
/// Окно на Mac: без серой полосы заголовка (кнопки окна поверх приложения), не меньше телефона,
/// при первом запуске — широкое, чтобы сразу открылась раскладка для компьютера с боковым меню.
enum MacWindow {
    static func setup(_ w: UIWindow) {
        guard let ws = w.windowScene else { DispatchQueue.main.async { if w.windowScene != nil { setup(w) } }; return }
        ws.title = "Финплан"
        ws.titlebar?.titleVisibility = .hidden
        ws.titlebar?.toolbar = nil
        ws.sizeRestrictions?.minimumSize = CGSize(width: 400, height: 640)
        if !UserDefaults.standard.bool(forKey: "macSized") {
            UserDefaults.standard.set(true, forKey: "macSized")
            ws.requestGeometryUpdate(.Mac(systemFrame: CGRect(x: 120, y: 80, width: 1280, height: 840)))
        }
    }
}
#endif
