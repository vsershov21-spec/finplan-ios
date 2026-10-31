import AppIntents
import Foundation

/// Ключ для записи СМС: приложение получает его с сервера по кнопке «Подключить СМС» и хранит в общей группе.
enum SMSKey {
    private static var store: UserDefaults { UserDefaults(suiteName: SharedStore.group) ?? .standard }
    static var token: String? {
        get { store.string(forKey: "smsToken") }
        set { store.set(newValue, forKey: "smsToken") }
    }
}

/// Действие для «Команд»: текст СМС банка → подборка в Финплане. Ключи и адреса вписывать не нужно.
struct LogBankSMS: AppIntent {
    static var title: LocalizedStringResource = "Записать СМС из банка"
    static var description = IntentDescription("Финплан разберёт сумму, магазин и категорию и положит операцию в подборку на главной.")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Текст СМС")
    var text: String

    @Parameter(title: "Отправитель", default: "")
    var sender: String

    static var parameterSummary: some ParameterSummary {
        Summary("Записать \(\.$text) от \(\.$sender)")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        guard let tok = SMSKey.token, !tok.isEmpty else {
            return .result(value: "", dialog: "Откройте Финплан → Траты из СМС → «Подключить на этом iPhone»")
        }
        var url = WebViewController.base.appendingPathComponent("api.php")
        url.append(queryItems: [URLQueryItem(name: "a", value: "quick"), URLQueryItem(name: "out", value: "json")])
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 20
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(tok)", forHTTPHeaderField: "Authorization")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["text": text, "sender": sender])
        let (data, _) = try await URLSession.shared.data(for: req)
        let msg = ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])?["message"] as? String ?? "Готово"
        return .result(value: msg, dialog: IntentDialog(stringLiteral: msg))
    }
}

struct FinShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: LogBankSMS(), phrases: ["Записать СМС в \(.applicationName)"], shortTitle: "Записать СМС", systemImageName: "message")
    }
}
