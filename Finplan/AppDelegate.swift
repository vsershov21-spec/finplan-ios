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
        let w = UIWindow(frame: UIScreen.main.bounds)
        w.backgroundColor = UIColor(named: "Paper")
        w.rootViewController = web
        w.makeKeyAndVisible()
        window = w
        // если пуши уже разрешены — обновим токен (Apple может его сменить)
        UNUserNotificationCenter.current().getNotificationSettings { s in
            if s.authorizationStatus == .authorized || s.authorizationStatus == .provisional {
                DispatchQueue.main.async { application.registerForRemoteNotifications() }
            }
        }
        return true
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
