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
        QuickActions.install()
        // окно создаёт SceneDelegate (жизненный цикл UIScene, которого требует Apple)
        // если пуши уже разрешены — обновим токен (Apple может его сменить)
        UNUserNotificationCenter.current().getNotificationSettings { s in
            if s.authorizationStatus == .authorized || s.authorizationStatus == .provisional {
                DispatchQueue.main.async { application.registerForRemoteNotifications() }
            }
        }
        return true
    }

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let c = UISceneConfiguration(name: "Default", sessionRole: connectingSceneSession.role)
        c.delegateClass = SceneDelegate.self
        return c
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

/// Окно приложения. Сюда же приходят ссылки finplan:// и быстрые действия со значка.
final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    private var web: WebViewController? { (UIApplication.shared.delegate as? AppDelegate)?.web }

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        guard let ws = scene as? UIWindowScene, let web else { return }
        if let u = options.urlContexts.first?.url { web.pendingTarget = WebViewController.target(fromDeepLink: u) }
        if let sc = options.shortcutItem { web.pendingTarget = sc.type }
        let w = UIWindow(windowScene: ws)
        w.backgroundColor = UIColor(named: "Paper")
        w.rootViewController = web
        w.makeKeyAndVisible()
        window = w
        #if targetEnvironment(macCatalyst)
        MacWindow.setup(w)
        #endif
    }

    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        if let u = URLContexts.first?.url { web?.open(target: WebViewController.target(fromDeepLink: u)) }
    }

    // долгое нажатие на значок: «Трата», «Доход», «Что впереди», «Из банка»
    func windowScene(_ windowScene: UIWindowScene, performActionFor shortcutItem: UIApplicationShortcutItem, completionHandler: @escaping (Bool) -> Void) {
        web?.open(target: shortcutItem.type); completionHandler(true)
    }
}
