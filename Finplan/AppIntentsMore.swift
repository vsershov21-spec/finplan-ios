import AppIntents
import UIKit

/// Открыть нужный раздел Финплана: из Siri, Spotlight, кнопки «Действие» и Пункта управления.
enum FinTarget: String, AppEnum {
    case spend, income, agenda, bank, home, forecast, goals
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Раздел Финплана"
    static var caseDisplayRepresentations: [FinTarget: DisplayRepresentation] = [
        .spend: "Новая трата", .income: "Новый доход", .agenda: "Что впереди", .bank: "Подборка из банка",
        .home: "Главная", .forecast: "Прогноз", .goals: "Цели"
    ]
    var webTarget: String { self == .goals ? "money" : rawValue }
}

struct OpenFinplan: AppIntent {
    static var title: LocalizedStringResource = "Открыть в Финплане"
    static var description = IntentDescription("Открывает Финплан сразу на нужном экране.")
    static var openAppWhenRun: Bool = true
    @Parameter(title: "Раздел", default: .spend) var target: FinTarget
    init() {}
    init(target: FinTarget) { self.target = target }
    static var parameterSummary: some ParameterSummary { Summary("Открыть \\(\\.$target)") }
    @MainActor func perform() async throws -> some IntentResult {
        (UIApplication.shared.delegate as? AppDelegate)?.web.open(target: target.webTarget)
        return .result()
    }
}

/// «Siri, запиши трату в Финплан»: сумма и что купили, без открытия приложения.
struct LogSpend: AppIntent {
    static var title: LocalizedStringResource = "Записать трату"
    static var description = IntentDescription("Сумма и короткое описание. Категорию Финплан подберёт по правилам.")
    static var openAppWhenRun: Bool = false
    @Parameter(title: "Сумма, ₽") var amount: Double
    @Parameter(title: "На что", default: "") var note: String
    static var parameterSummary: some ParameterSummary { Summary("Записать \\(\\.$amount) ₽ на \\(\\.$note)") }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let tok = SMSKey.token, !tok.isEmpty else {
            return .result(dialog: "Сначала откройте Финплан → Траты из СМС → «Подключить на этом iPhone»")
        }
        var url = WebViewController.base.appendingPathComponent("api.php")
        url.append(queryItems: [URLQueryItem(name: "a", value: "quick"), URLQueryItem(name: "out", value: "json")])
        var req = URLRequest(url: url); req.httpMethod = "POST"; req.timeoutInterval = 20
        req.setValue("application/json", forHTTPHeaderField: "Content-Type"); req.setValue("Bearer \\(tok)", forHTTPHeaderField: "Authorization")
        let sum = amount.rounded() == amount ? String(Int(amount)) : String(amount)
        req.httpBody = try JSONSerialization.data(withJSONObject: ["text": "\\(sum) \\(note)".trimmingCharacters(in: .whitespaces)])
        let (data, _) = try await URLSession.shared.data(for: req)
        let msg = ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])?["message"] as? String ?? "Записано"
        return .result(dialog: IntentDialog(stringLiteral: msg))
    }
}
