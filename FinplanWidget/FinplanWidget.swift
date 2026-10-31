import WidgetKit
import SwiftUI

struct FinEntry: TimelineEntry {
    let date: Date
    let snap: FinSnapshot?
}

struct FinProvider: TimelineProvider {
    func placeholder(in context: Context) -> FinEntry { FinEntry(date: Date(), snap: .sample) }
    func getSnapshot(in context: Context, completion: @escaping (FinEntry) -> Void) {
        completion(FinEntry(date: Date(), snap: context.isPreview ? (SharedStore.load() ?? .sample) : SharedStore.load()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<FinEntry>) -> Void) {
        // данные приходят из приложения; Кузьма меняет настроение сам: в обычное время записей, вечером и когда давно не заходили
        let snap = SharedStore.load(), now = Date(), cal = Calendar.current
        var dates: [Date] = [now]
        if let s = snap {
            if let at = s.nudgeAt, let t = Kuzya.minutes(at), let d = cal.date(bySettingHour: t / 60, minute: t % 60, second: 0, of: now), d > now { dates.append(d) }
            if let d = cal.date(bySettingHour: 21, minute: 0, second: 0, of: now), d > now { dates.append(d) }
            if let d = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now)) { dates.append(d) }
            let upd = Date(timeIntervalSince1970: s.updated)
            for days in [3, 7] { if let d = cal.date(byAdding: .day, value: days, to: upd), d > now { dates.append(d) } }
        }
        let entries = dates.sorted().map { FinEntry(date: $0, snap: snap) }
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(3 * 3600))))
    }
}

// MARK: - Кузьма

enum Kuzya {
    static func minutes(_ hhmm: String) -> Int? {
        let p = hhmm.split(separator: ":"); guard p.count == 2, let h = Int(p[0]), let m = Int(p[1]) else { return nil }; return h * 60 + m
    }
    /// Настроение и строка на момент `date`: приложение могло давно не открываться, поэтому считаем сами.
    static func state(_ s: FinSnapshot, at date: Date) -> (mood: String, text: String) {
        let cal = Calendar.current, upd = Date(timeIntervalSince1970: s.updated)
        let idle = cal.dateComponents([.day], from: cal.startOfDay(for: upd), to: cal.startOfDay(for: date)).day ?? 0
        let streak = s.streak ?? 0
        let wroteToday = (s.today ?? false) && cal.isDate(upd, inSameDayAs: date)
        let mins = cal.component(.hour, from: date) * 60 + cal.component(.minute, from: date)
        if idle >= 7 { return ("angry", "Неделю не виделись. Цифры устарели") }
        if idle >= 3 { return ("sleep", "Давно не виделись. Откройте, чтобы обновить") }
        if (s.bank ?? 0) > 0 && idle == 0 { return ("please", "Из банка: \(s.bank!). Примите одним касанием") }
        if !wroteToday && streak >= 3 && mins >= 21 * 60 { return ("worry", "Серия \(streak) \(days(streak)) сгорит в полночь") }
        if !wroteToday, let at = s.nudgeAt, let t = minutes(at), mins >= t { return ("wait", "Что было сегодня? Запишите траты") }
        if idle == 0, let m = s.kz, let t = s.kzText, ["ok", "party"].contains(m) { return (m, t) }
        return ("ok", streak > 0 ? "Серия \(streak) \(days(streak))" : "Записывайте каждый день")
    }
    static func days(_ n: Int) -> String {
        let a = n % 100, b = n % 10
        if a > 10 && a < 20 { return "дней" }; if b == 1 { return "день" }; if b > 1 && b < 5 { return "дня" }; return "дней"
    }
}

struct KuzyaBubble: View {
    let mood: String
    let text: String
    var size: CGFloat = 44
    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            Image("Kuzya-\(mood)").resizable().scaledToFit().frame(width: size, height: size)
            Text(text).font(.caption2.weight(.semibold)).lineLimit(2).minimumScaleFactor(0.85).fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - цвета как в приложении

extension Color {
    static let finIn = Color(red: 0.20, green: 0.78, blue: 0.35)
    static let finOut = Color(red: 1.0, green: 0.27, blue: 0.23)
    static let finWarn = Color(red: 1.0, green: 0.58, blue: 0.0)
    static let finAccent = Color(red: 0.0, green: 0.48, blue: 1.0)
}

private func updatedText(_ s: FinSnapshot) -> String {
    guard s.updated > 0 else { return "" }
    let d = Date(timeIntervalSince1970: s.updated)
    let f = DateFormatter(); f.locale = Locale(identifier: "ru_RU")
    f.dateFormat = Calendar.current.isDateInToday(d) ? "HH:mm" : "d MMM"
    return f.string(from: d)
}

private func nextText(_ n: FinSnapshot.Next) -> String {
    let parts = n.date.split(separator: "-")
    guard parts.count == 3, let m = Int(parts[1]), let d = Int(parts[2]) else { return n.name }
    let mon = ["янв", "фев", "мар", "апр", "мая", "июн", "июл", "авг", "сен", "окт", "ноя", "дек"][max(0, min(11, m - 1))]
    return "\(d) \(mon) · \(n.name)"
}

struct Bar: View {
    let value: Double
    let color: Color
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.1))
                Capsule().fill(color).frame(width: max(4, g.size.width * min(1, max(0, value))))
            }
        }
        .frame(height: 5)
    }
}

struct Header: View {
    let snap: FinSnapshot
    var body: some View {
        HStack(spacing: 6) {
            Image("Logo").resizable().frame(width: 16, height: 16).clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            Text("Ваши деньги").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Text(updatedText(snap)).font(.caption2).foregroundStyle(.tertiary)
        }
    }
}

struct EmptyStateView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image("Logo").resizable().frame(width: 28, height: 28).clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            Spacer(minLength: 0)
            Text("Финплан").font(.headline)
            Text("Откройте приложение — здесь появятся ваши деньги").font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

struct SmallView: View {
    let s: FinSnapshot
    let date: Date
    var body: some View {
        let k = Kuzya.state(s, at: date), stale = ["sleep", "angry"].contains(k.mood)
        VStack(alignment: .leading, spacing: 4) {
            Header(snap: s)
            Spacer(minLength: 0)
            Text(Money.rub(s.balance)).font(.system(size: 26, weight: .bold, design: .rounded)).minimumScaleFactor(0.5).lineLimit(1)
                .foregroundStyle(stale ? .secondary : .primary)
            if k.mood != "ok" {
                KuzyaBubble(mood: k.mood, text: k.text, size: 40)
            } else if s.due > 0 {
                Label(s.due == 1 ? "Пора оплатить" : "Оплатить: \(s.due)", systemImage: "exclamationmark.circle.fill")
                    .font(.caption.weight(.semibold)).foregroundStyle(Color.finWarn).lineLimit(1)
            } else if s.spendPlan > 0 {
                Bar(value: s.spent / s.spendPlan, color: s.spent > s.spendPlan ? .finOut : .finAccent)
                Text("траты \(Money.short(s.spent)) из \(Money.short(s.spendPlan))").font(.caption2).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
            }
        }
    }
}

struct MediumView: View {
    let s: FinSnapshot
    let date: Date
    var body: some View {
        let k = Kuzya.state(s, at: date), stale = ["sleep", "angry"].contains(k.mood)
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Header(snap: s)
                Spacer(minLength: 0)
                Text(Money.rub(s.balance)).font(.system(size: 28, weight: .bold, design: .rounded)).minimumScaleFactor(0.5).lineLimit(1)
                    .foregroundStyle(stale ? .secondary : .primary)
                KuzyaBubble(mood: k.mood, text: k.text, size: 46)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .leading, spacing: 8) {
                if s.due > 0 {
                    VStack(alignment: .leading, spacing: 2) {
                        Label("Пора оплатить", systemImage: "exclamationmark.circle.fill").font(.caption.weight(.semibold)).foregroundStyle(Color.finWarn)
                        Text(s.dueTitle.replacingOccurrences(of: "Оплатить: ", with: "")).font(.caption2).lineLimit(2)
                    }
                }
                VStack(alignment: .leading, spacing: 3) {
                    HStack { Text("Траты").font(.caption2).foregroundStyle(.secondary); Spacer(); Text(Money.short(s.spent)).font(.caption2.weight(.semibold)) }
                    Bar(value: s.spendPlan > 0 ? s.spent / s.spendPlan : 0, color: s.spent > s.spendPlan ? .finOut : .finAccent)
                }
                VStack(alignment: .leading, spacing: 3) {
                    HStack { Text("Доходы").font(.caption2).foregroundStyle(.secondary); Spacer(); Text(Money.short(s.got)).font(.caption2.weight(.semibold)) }
                    Bar(value: s.incomePlan > 0 ? s.got / s.incomePlan : 0, color: .finIn)
                }
                if s.due == 0, let n = s.next {
                    Text("₽ \(Money.short(n.amount)) · \(nextText(n))").font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .frame(width: 140)
        }
    }
}

private func widgetLink(_ e: FinEntry) -> String {
    guard let s = e.snap else { return "finplan://home" }
    switch Kuzya.state(s, at: e.date).mood {
    case "please": return "finplan://bank"
    case "wait", "worry": return "finplan://spend"
    default: return s.due > 0 ? "finplan://plan" : "finplan://home"
    }
}

struct FinWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: FinEntry
    var body: some View {
        Group {
            if let s = entry.snap {
                switch family {
                case .accessoryInline:
                    Text(s.due > 0 ? "₽ \(Money.short(s.balance)) · оплатить \(s.due)" : "₽ \(Money.short(s.balance))")
                case .accessoryRectangular:
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Финплан").font(.caption2.weight(.semibold))
                        Text(Money.rub(s.balance)).font(.headline).minimumScaleFactor(0.6).lineLimit(1)
                        Text(Kuzya.state(s, at: entry.date).mood != "ok" ? Kuzya.state(s, at: entry.date).text : s.due > 0 ? "пора оплатить: \(s.due)" : "траты \(Money.short(s.spent)) из \(Money.short(s.spendPlan))").font(.caption2).lineLimit(1)
                    }
                case .accessoryCircular:
                    Gauge(value: s.spendPlan > 0 ? min(1, s.spent / s.spendPlan) : 0) {
                        Text("₽")
                    } currentValueLabel: {
                        Text(s.spendPlan > 0 ? "\(Int(min(999, (s.spent / s.spendPlan * 100).rounded())))" : "—")
                    }
                    .gaugeStyle(.accessoryCircularCapacity)
                case .systemMedium:
                    MediumView(s: s, date: entry.date)
                default:
                    SmallView(s: s, date: entry.date)
                }
            } else {
                if family == .accessoryInline || family == .accessoryRectangular || family == .accessoryCircular {
                    Text("Финплан")
                } else {
                    EmptyStateView()
                }
            }
        }
        .widgetURL(URL(string: widgetLink(entry)))
        .containerBackground(for: .widget) { Color(UIColor.systemBackground) }
    }
}

@main
struct FinplanWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "FinplanBalance", provider: FinProvider()) { entry in
            FinWidgetView(entry: entry)
        }
        .configurationDisplayName("Финплан")
        .description("Ваши деньги, траты месяца и Кузьма, который напомнит записать.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline, .accessoryCircular])
    }
}
