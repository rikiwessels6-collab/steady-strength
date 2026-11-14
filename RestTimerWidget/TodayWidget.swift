import SwiftUI
import WidgetKit

private enum Tide {
    static let night = Color(red: 0x0B / 255, green: 0x22 / 255, blue: 0x30 / 255)
    static let surface = Color(red: 0x12 / 255, green: 0x31 / 255, blue: 0x3F / 255)
    static let coral = Color(red: 0xFF / 255, green: 0x7A / 255, blue: 0x59 / 255)
    static let aqua = Color(red: 0x2E / 255, green: 0xC4 / 255, blue: 0xB6 / 255)
    static let ink = Color(red: 0xEE / 255, green: 0xF8 / 255, blue: 0xF8 / 255)
    static let muted = Color(red: 0x93 / 255, green: 0xB6 / 255, blue: 0xBF / 255)
}

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry { SnapshotEntry(date: .now, snapshot: .sample) }
    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        completion(SnapshotEntry(date: .now, snapshot: context.isPreview ? .sample : WidgetSnapshot.load()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        // The app asks for a reload whenever its numbers change; refresh hourly as well so "today" rolls over.
        let entry = SnapshotEntry(date: .now, snapshot: WidgetSnapshot.load())
        completion(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(3600))))
    }
}

/// Home screen: next session, calories left, water and sleep. Lock screen: calories left or the next session.
struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "SteadyToday", provider: SnapshotProvider()) { entry in
            TodayWidgetView(entry: entry)
        }
        .configurationDisplayName("Steady Strength today")
        .description("Your next session, calories left, water and sleep.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryCircular, .accessoryInline])
    }
}

struct TodayWidgetView: View {
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family

    private var stale: Bool {
        guard let s = entry.snapshot else { return true }
        return !Calendar.current.isDateInToday(s.updated)
    }

    var body: some View {
        Group {
            if let s = entry.snapshot {
                switch family {
                case .accessoryCircular: circular(s)
                case .accessoryRectangular: rectangular(s)
                case .accessoryInline: Text(kcalLeftText(s)).privacySensitive()
                case .systemMedium: medium(s)
                default: small(s)
                }
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Steady Strength").font(.headline)
                    Text("Open the app once to fill this in.").font(.caption).foregroundStyle(Tide.muted)
                }
            }
        }
        .containerBackground(for: .widget) { Tide.night }
        .widgetURL(URL(string: "steadystrength://today"))
    }

    private func kcalLeft(_ s: WidgetSnapshot) -> Int { stale ? s.kcalTarget : s.kcalTarget - s.kcalEaten }
    private func kcalLeftText(_ s: WidgetSnapshot) -> String {
        let left = kcalLeft(s)
        return left >= 0 ? "\(left.formatted()) kcal left" : "\((-left).formatted()) kcal over"
    }
    private func share(_ value: Int, _ target: Int) -> Double { target > 0 ? min(1, max(0, Double(value) / Double(target))) : 0 }

    private func small(_ s: WidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("NEXT").font(.caption2.weight(.bold)).foregroundStyle(Tide.coral)
            Text(s.nextSession ?? "Rest day").font(.headline).foregroundStyle(Tide.ink).lineLimit(2).minimumScaleFactor(0.8)
            Spacer(minLength: 0)
            Gauge(value: stale ? 0 : share(s.kcalEaten, s.kcalTarget)) { EmptyView() }
                .gaugeStyle(.accessoryLinearCapacity).tint(Tide.aqua)
            Text(kcalLeftText(s)).font(.caption.monospacedDigit()).foregroundStyle(Tide.muted).privacySensitive()
        }
    }

    private func medium(_ s: WidgetSnapshot) -> some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("NEXT SESSION").font(.caption2.weight(.bold)).foregroundStyle(Tide.coral)
                Text(s.nextSession ?? "Rest day").font(.headline).foregroundStyle(Tide.ink).lineLimit(2)
                if let w = s.weekLabel { Text(w).font(.caption).foregroundStyle(Tide.muted) }
                Spacer(minLength: 0)
                if s.streakWeeks >= 2 {
                    Label("\(s.streakWeeks) weeks in a row", systemImage: "flame.fill").font(.caption2).foregroundStyle(Tide.coral)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .leading, spacing: 8) {
                row("Food", kcalLeftText(s), stale ? 0 : share(s.kcalEaten, s.kcalTarget))
                row("Protein", "\(stale ? 0 : s.proteinEaten) / \(s.proteinTarget) g", stale ? 0 : share(s.proteinEaten, s.proteinTarget))
                row("Water", String(format: "%.1f / %.1f L", stale ? 0 : Double(s.waterMl) / 1000, Double(s.waterGoalMl) / 1000),
                    stale ? 0 : share(s.waterMl, s.waterGoalMl))
                if let h = s.sleepHours, !stale {
                    Label(String(format: "%.1f h sleep", h), systemImage: "moon.fill").font(.caption2).foregroundStyle(Tide.muted)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .privacySensitive()
        }
    }

    private func row(_ label: String, _ value: String, _ share: Double) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label).font(.caption2.weight(.semibold)).foregroundStyle(Tide.ink)
                Spacer(minLength: 4)
                Text(value).font(.caption2.monospacedDigit()).foregroundStyle(Tide.muted).lineLimit(1).minimumScaleFactor(0.7)
            }
            Gauge(value: share) { EmptyView() }.gaugeStyle(.accessoryLinearCapacity).tint(Tide.aqua)
        }
    }

    private func circular(_ s: WidgetSnapshot) -> some View {
        Gauge(value: stale ? 0 : share(s.kcalEaten, s.kcalTarget)) {
            Image(systemName: "fork.knife")
        } currentValueLabel: {
            Text("\(max(0, kcalLeft(s)))").privacySensitive()
        }
        .gaugeStyle(.accessoryCircularCapacity)
    }

    private func rectangular(_ s: WidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(s.nextSession.map { "Next: \($0)" } ?? "Rest day").font(.headline).lineLimit(1)
            Text(kcalLeftText(s)).font(.caption).privacySensitive()
            if let h = s.sleepHours, !stale { Text(String(format: "Slept %.1f h", h)).font(.caption).privacySensitive() }
        }
    }
}
