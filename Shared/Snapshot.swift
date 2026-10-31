import Foundation

/// Сводка для виджета: её присылает экран «Главная» при каждом обновлении.
struct FinSnapshot: Codable, Equatable {
    struct Next: Codable, Equatable {
        var name: String
        var amount: Double
        var date: String
    }
    var name: String = ""
    var balance: Double = 0
    var family: Double = 0
    var shared: Double = 0
    var spent: Double = 0
    var spendPlan: Double = 0
    var got: Double = 0
    var incomePlan: Double = 0
    var due: Int = 0
    var dueTitle: String = ""
    var next: Next? = nil
    var month: String = ""
    var updated: Double = 0
    // Кузьма: настроение и строка из приложения, серия дней с записями
    var kz: String? = nil
    var kzText: String? = nil
    var streak: Int? = nil
    var today: Bool? = nil
    var nudgeAt: String? = nil
    var bank: Int? = nil

    static let sample = FinSnapshot(name: "Владимир", balance: 998_356, family: 1_360_000, shared: 867_000, spent: 24_869, spendPlan: 84_000,
                                    got: 105_000, incomePlan: 499_000, due: 1, dueTitle: "Оплатить: Коммуналка", next: Next(name: "Сбер", amount: 142_000, date: "2026-11-05"), month: "ноябрь", updated: Date().timeIntervalSince1970, kz: "ok", kzText: "Серия 12 дней", streak: 12, today: true, nudgeAt: "21:30", bank: 0)
}

enum SharedStore {
    static let group = "group.com.vershov.finplan"
    static var defaults: UserDefaults { UserDefaults(suiteName: group) ?? .standard }

    static func save(_ snap: FinSnapshot) {
        if let d = try? JSONEncoder().encode(snap) { defaults.set(d, forKey: "snap") }
    }
    static func load() -> FinSnapshot? {
        guard let d = defaults.data(forKey: "snap") else { return nil }
        return try? JSONDecoder().decode(FinSnapshot.self, from: d)
    }
    static func clear() { defaults.removeObject(forKey: "snap") }
}

enum Money {
    private static let full: NumberFormatter = {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        f.groupingSeparator = "\u{00A0}"
        return f
    }()
    /// 998 356 ₽
    static func rub(_ v: Double) -> String {
        let s = full.string(from: NSNumber(value: v.rounded())) ?? "\(Int(v))"
        return s.replacingOccurrences(of: "-", with: "−") + "\u{00A0}₽"
    }
    /// 1,36 млн · 142 тыс · 870 ₽
    static func short(_ v: Double) -> String {
        let a = abs(v), sign = v < 0 ? "−" : ""
        func num(_ x: Double, _ digits: Int) -> String {
            let f = NumberFormatter(); f.locale = Locale(identifier: "ru_RU"); f.maximumFractionDigits = digits; f.minimumFractionDigits = 0
            return f.string(from: NSNumber(value: x)) ?? String(x)
        }
        if a >= 1_000_000 { return sign + num(a / 1_000_000, 2) + "\u{00A0}млн" }
        if a >= 10_000 { return sign + num((a / 1000).rounded(), 0) + "\u{00A0}тыс" }
        return rub(v)
    }
}
