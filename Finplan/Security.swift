import UIKit
import LocalAuthentication
import Security

/// Face ID / Touch ID: с запасным вводом кода iPhone.
enum Biometry {
    static var name: String {
        let c = LAContext()
        _ = c.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch c.biometryType {
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        default: return "Face ID"
        }
    }

    static func authenticate(reason: String, done: @escaping (Bool) -> Void) {
        let c = LAContext()
        c.localizedCancelTitle = "Отмена"
        var err: NSError?
        guard c.canEvaluatePolicy(.deviceOwnerAuthentication, error: &err) else { DispatchQueue.main.async { done(true) }; return } // на телефоне нет ни кода, ни Face ID — не запираем
        c.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { ok, _ in DispatchQueue.main.async { done(ok) } }
    }
}

/// Логин и пароль — в связке ключей, только на этом устройстве.
enum Keychain {
    private static let service = "com.vershov.finplan.login"

    static var hasCredentials: Bool { load() != nil }

    static func save(login: String, password: String) {
        clear()
        let data = (try? JSONSerialization.data(withJSONObject: ["l": login, "p": password])) ?? Data()
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "main",
                                kSecValueData as String: data, kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        SecItemAdd(q as CFDictionary, nil)
    }

    static func load() -> (login: String, password: String)? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "main",
                                kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data,
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: String], let l = o["l"], let p = o["p"] else { return nil }
        return (l, p)
    }

    static func clear() {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service]
        SecItemDelete(q as CFDictionary)
    }
}

/// Экран блокировки: размытие поверх сумм, значок и кнопка.
final class LockView: UIView {
    var onUnlock: (() -> Void)?
    private(set) var isShown = false
    private var busy = false
    private let blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemThickMaterial))
    private let stack = UIStackView()
    private let button = UIButton(type: .system)

    init() {
        super.init(frame: .zero)
        blur.translatesAutoresizingMaskIntoConstraints = false
        addSubview(blur)
        let logo = UIImageView(image: UIImage(named: "Logo"))
        logo.contentMode = .scaleAspectFit
        logo.layer.cornerRadius = 18; logo.clipsToBounds = true
        logo.widthAnchor.constraint(equalToConstant: 80).isActive = true
        logo.heightAnchor.constraint(equalToConstant: 80).isActive = true
        let title = UILabel()
        title.text = "Финплан"
        title.font = .systemFont(ofSize: 22, weight: .bold)
        var cfg = UIButton.Configuration.filled()
        cfg.cornerStyle = .capsule
        cfg.title = "Открыть по \(Biometry.name)"
        cfg.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 22, bottom: 12, trailing: 22)
        button.configuration = cfg
        button.addTarget(self, action: #selector(tap), for: .touchUpInside)
        stack.axis = .vertical; stack.alignment = .center; stack.spacing = 14
        [logo, title, button].forEach { stack.addArrangedSubview($0) }
        stack.setCustomSpacing(28, after: title)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            blur.topAnchor.constraint(equalTo: topAnchor), blur.bottomAnchor.constraint(equalTo: bottomAnchor),
            blur.leadingAnchor.constraint(equalTo: leadingAnchor), blur.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.centerXAnchor.constraint(equalTo: centerXAnchor), stack.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -40),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    /// coverOnly — только спрятать суммы (в переключателе приложений), без запроса Face ID
    func show(in host: UIView, coverOnly: Bool = false) {
        stack.isHidden = coverOnly
        if !isShown {
            frame = host.bounds; autoresizingMask = [.flexibleWidth, .flexibleHeight]; alpha = 1
            host.addSubview(self); isShown = true
        }
        host.bringSubviewToFront(self)
    }

    func hide() {
        guard isShown else { return }
        isShown = false
        UIView.animate(withDuration: 0.25, animations: { self.alpha = 0 }) { _ in if !self.isShown { self.removeFromSuperview(); self.alpha = 1 } }
    }

    func authenticate() {
        guard isShown, !busy else { return }
        stack.isHidden = false
        busy = true
        Biometry.authenticate(reason: "Открыть Финплан") { [weak self] ok in
            guard let self else { return }
            self.busy = false
            if ok { Haptics.play("success"); self.hide(); self.onUnlock?() }
        }
    }

    @objc private func tap() { authenticate() }
}

/// Нет связи: короткое сообщение и «Повторить».
final class OfflineView: UIView {
    var onRetry: (() -> Void)?
    private let label = UILabel()

    init() {
        super.init(frame: .zero)
        backgroundColor = UIColor(named: "Paper")
        let title = UILabel(); title.text = "Нет связи с Финпланом"; title.font = .systemFont(ofSize: 20, weight: .bold); title.textAlignment = .center
        label.font = .systemFont(ofSize: 15); label.textColor = .secondaryLabel; label.numberOfLines = 0; label.textAlignment = .center
        var cfg = UIButton.Configuration.filled(); cfg.cornerStyle = .capsule; cfg.title = "Повторить"
        cfg.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 26, bottom: 12, trailing: 26)
        let b = UIButton(configuration: cfg); b.addTarget(self, action: #selector(retry), for: .touchUpInside)
        let s = UIStackView(arrangedSubviews: [title, label, b]); s.axis = .vertical; s.alignment = .center; s.spacing = 12; s.setCustomSpacing(24, after: label)
        s.translatesAutoresizingMaskIntoConstraints = false
        addSubview(s)
        NSLayoutConstraint.activate([s.centerYAnchor.constraint(equalTo: centerYAnchor), s.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 32), s.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -32)])
    }
    required init?(coder: NSCoder) { fatalError() }

    func show(in host: UIView, message: String) {
        label.text = message
        frame = host.bounds; autoresizingMask = [.flexibleWidth, .flexibleHeight]
        if superview == nil { host.addSubview(self) }
        host.bringSubviewToFront(self)
    }
    func hide() { removeFromSuperview() }
    @objc private func retry() { onRetry?() }
}
