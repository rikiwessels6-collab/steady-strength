import Foundation

/// Harder training days: the user marks a day, and that day's calorie target rises by an amount
/// they choose in Settings, all of it as carbohydrate. The weekly calorie suggestion still works from
/// the weight trend, so this is a day-to-day shift, not a change to the plan.
public enum HardDay {
    public static let defaultExtraKcal = 200
    public static let maxKept = 120

    /// A calendar day as "yyyy-MM-dd" in the user's time zone.
    public static func key(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// The day's targets: extra calories go to carbs at 4 kcal per gram.
    public static func targets(calories: Int, carbs: Int, extraKcal: Int, isHardDay: Bool) -> (calories: Int, carbs: Int) {
        guard isHardDay, extraKcal > 0 else { return (calories, carbs) }
        return (calories + extraKcal, carbs + Int((Double(extraKcal) / 4).rounded()))
    }

    /// Calories added back from workouts recorded in Apple Health: the chosen share of their active energy,
    /// rounded to the nearest 10. Watch and app estimates vary, which is why the share is the user's to set.
    public static func healthExtra(burnedKcal: Int, percent: Int) -> Int {
        guard burnedKcal > 0, percent > 0 else { return 0 }
        return Int((Double(burnedKcal) * Double(min(percent, 100)) / 100 / 10).rounded()) * 10
    }

    /// The day's extra: the larger of the hard-day amount (if marked) and the Health add-back, never both,
    /// so a hard session recorded on a watch isn't counted twice.
    public static func extra(manualKcal: Int, isHardDay: Bool, healthKcal: Int) -> Int {
        max(isHardDay ? manualKcal : 0, healthKcal, 0)
    }

    /// Marks or unmarks a day, keeping only the most recent days.
    public static func toggled(_ days: [String], key: String) -> [String] {
        var set = Set(days)
        if set.contains(key) { set.remove(key) } else { set.insert(key) }
        return Array(set.sorted().suffix(maxKept))
    }
}
