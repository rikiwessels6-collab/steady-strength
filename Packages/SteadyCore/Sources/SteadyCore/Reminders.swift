import Foundation

/// A repeating weekly reminder. The app turns these into local notifications (nothing leaves the phone).
public struct ReminderSlot: Equatable, Sendable, Identifiable {
    public var id: String
    public var weekday: Int      // 1 = Sunday ... 7 = Saturday
    public var hour: Int
    public var minute: Int
    public var title: String
    public var body: String
}

public enum Reminders {
    public static let idPrefix = "steady."

    /// One reminder per training weekday and one for the weekly check-in. Plain, neutral wording.
    public static func slots(trainingWeekdays: [Int], checkInWeekday: Int?, hour: Int, minute: Int) -> [ReminderSlot] {
        let h = min(max(hour, 0), 23), m = min(max(minute, 0), 59)
        var out: [ReminderSlot] = Set(trainingWeekdays).filter { (1...7).contains($0) }.sorted().map {
            ReminderSlot(id: "\(idPrefix)session.\($0)", weekday: $0, hour: h, minute: m,
                         title: "Training day", body: "Your session is ready when you are.")
        }
        if let c = checkInWeekday, (1...7).contains(c) {
            out.append(ReminderSlot(id: "\(idPrefix)checkin", weekday: c, hour: h, minute: m,
                                    title: "Weekly check-in", body: "It only takes a minute."))
        }
        return out
    }
}

/// "Did you log lunch?" nudges. Each is a one-off notification for a specific day, scheduled a week ahead
/// and refreshed whenever the app opens or food is logged, so a meal that's already logged today gets no nudge.
public enum MealReminders {
    public static let idPrefix = "meal."
    public static let daysAhead = 7
    /// Minutes after midnight: 9:30 am, 1:30 pm, 7:30 pm. Late enough that the meal has usually been eaten.
    public static let defaultTimes: [MealSlot: Int] = [.breakfast: 570, .lunch: 810, .dinner: 1170]

    public struct Planned: Equatable, Sendable {
        public let id: String
        public let meal: MealSlot
        public let date: Date
        public let title: String
        public let body: String
    }

    /// The meal a notification id belongs to ("meal.lunch.2026-11-18" -> lunch).
    public static func meal(fromId id: String) -> MealSlot? {
        guard id.hasPrefix(idPrefix) else { return nil }
        return MealSlot(rawValue: String(id.dropFirst(idPrefix.count).prefix { $0 != "." }))
    }

    /// Reminders for today and the next days, leaving out times already past and meals already logged today.
    public static func plan(times: [MealSlot: Int], loggedToday: Set<MealSlot>, now: Date = .now,
                            days: Int = daysAhead, calendar: Calendar = .current) -> [Planned] {
        let today = calendar.startOfDay(for: now)
        var out: [Planned] = []
        for offset in 0..<max(days, 1) {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
            let c = calendar.dateComponents([.year, .month, .day], from: day)
            let key = String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
            for meal in MealSlot.allCases {
                guard let minutes = times[meal] else { continue }
                let m = min(max(minutes, 0), 24 * 60 - 1)
                guard let at = calendar.date(bySettingHour: m / 60, minute: m % 60, second: 0, of: day), at > now else { continue }
                if offset == 0 && loggedToday.contains(meal) { continue }
                out.append(Planned(id: "\(idPrefix)\(meal.rawValue).\(key)", meal: meal, date: at,
                                   title: "Log \(meal.label.lowercased())?",
                                   body: "Nothing's in \(meal.label.lowercased()) yet. Tap to add it: search, scan a barcode or take a plate photo."))
            }
        }
        return out.sorted { $0.date < $1.date }
    }
}
