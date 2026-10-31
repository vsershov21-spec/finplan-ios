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
        // данные приходят из приложения; раз в час перерисовываем «обновлено …»
        let e = FinEntry(date: Date(), snap: SharedStore.load())
        completion(Timeline(entries: [e], policy: .after(Date().addingTimeInterval(3600))))
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
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Header(snap: s)
            Spacer(minLength: 0)
            Text(Money.rub(s.balance)).font(.system(size: 26, weight: .bold, design: .rounded)).minimumScaleFactor(0.5).lineLimit(1)
            if s.due > 0 {
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
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Header(snap: s)
                Spacer(minLength: 0)
                Text(Money.rub(s.balance)).font(.system(size: 28, weight: .bold, design: .rounded)).minimumScaleFactor(0.5).lineLimit(1)
                Text("вместе \(Money.short(s.family)) · общее \(Money.short(s.shared))").font(.caption2).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
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
                        Text(s.due > 0 ? "пора оплатить: \(s.due)" : "траты \(Money.short(s.spent)) из \(Money.short(s.spendPlan))").font(.caption2).lineLimit(1)
                    }
                case .accessoryCircular:
                    Gauge(value: s.spendPlan > 0 ? min(1, s.spent / s.spendPlan) : 0) {
                        Text("₽")
                    } currentValueLabel: {
                        Text(s.spendPlan > 0 ? "\(Int(min(999, (s.spent / s.spendPlan * 100).rounded())))" : "—")
                    }
                    .gaugeStyle(.accessoryCircularCapacity)
                case .systemMedium:
                    MediumView(s: s)
                default:
                    SmallView(s: s)
                }
            } else {
                if family == .accessoryInline || family == .accessoryRectangular || family == .accessoryCircular {
                    Text("Финплан")
                } else {
                    EmptyStateView()
                }
            }
        }
        .widgetURL(URL(string: (entry.snap?.due ?? 0) > 0 ? "finplan://plan" : "finplan://home"))
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
        .description("Ваши деньги, траты месяца и что пора оплатить.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline, .accessoryCircular])
    }
}
