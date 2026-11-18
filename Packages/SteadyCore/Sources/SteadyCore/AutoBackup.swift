import Foundation

/// When the weekly backup is due, what the files are called, and which old ones to remove.
public enum AutoBackupPlan {
    public static let intervalDays = 7
    /// How many backup files to keep in the folder.
    public static let keep = 8
    public static let prefix = "SteadyStrength-backup-"

    /// Due when there has never been one, or the last was a week ago. An hour's slack so
    /// opening the app at about the same time each week still counts.
    public static func isDue(last: Date?, now: Date = .now, intervalDays: Int = intervalDays) -> Bool {
        guard let last else { return true }
        return now.timeIntervalSince(last) >= Double(intervalDays) * 86_400 - 3_600
    }

    /// "SteadyStrength-backup-2026-11-18.json". Names sort by date.
    public static func fileName(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return prefix + String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0) + ".json"
    }

    /// The app's own backup files beyond the newest `keep`. Anything else in the folder is left alone.
    public static func toRemove(_ names: [String], keep: Int = keep) -> [String] {
        let ours = names.filter { $0.hasPrefix(prefix) && $0.hasSuffix(".json") }.sorted(by: >)
        return Array(ours.dropFirst(max(keep, 1)))
    }
}

/// Copying past food onto another day.
public enum FoodRepeat {
    /// The same time of day on `day`, but never later than `now`.
    public static func time(of original: Date, on day: Date, now: Date = .now, calendar: Calendar = .current) -> Date {
        let t = calendar.dateComponents([.hour, .minute], from: original)
        let when = calendar.date(bySettingHour: t.hour ?? 12, minute: t.minute ?? 0, second: 0, of: day) ?? day
        return min(when, now)
    }

    /// The start of the most recent day before `day` that has anything logged.
    public static func previousDay(_ dates: [Date], before day: Date, calendar: Calendar = .current) -> Date? {
        let start = calendar.startOfDay(for: day)
        return dates.filter { $0 < start }.max().map { calendar.startOfDay(for: $0) }
    }
}
