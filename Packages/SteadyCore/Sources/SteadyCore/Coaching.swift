import Foundation

extension ExerciseStats {
    /// True when the sets in `during` beat everything in `before` for top weight or estimated 1RM.
    /// A first-ever session is not a record: there is nothing to beat yet.
    public static func isRecord(before: [StatSet], during: [StatSet], calendar: Calendar = .current) -> Bool {
        let old = sessions(before.filter { $0.weight > 0 }, calendar: calendar)
        let new = sessions(during.filter { $0.weight > 0 }, calendar: calendar)
        guard !old.isEmpty, !new.isEmpty else { return false }
        let oldWeight = old.map(\.topWeight).max() ?? 0
        let oldOneRM = old.map(\.estimatedOneRepMax).max() ?? 0
        return new.contains { $0.topWeight > oldWeight || $0.estimatedOneRepMax > oldOneRM }
    }
}

/// How many weeks in a row the planned number of sessions was done.
public enum Consistency {
    /// Counts back from last week; the current week is added once it has already reached the plan
    /// (a week still in progress never breaks the streak).
    public static func weekStreak(sessionDates: [Date], planned: Int, now: Date = .now,
                                  calendar: Calendar = Calendar(identifier: .iso8601)) -> Int {
        guard planned > 0, let thisWeek = calendar.dateInterval(of: .weekOfYear, for: now)?.start else { return 0 }
        var perWeek: [Date: Int] = [:]
        for d in sessionDates {
            if let start = calendar.dateInterval(of: .weekOfYear, for: d)?.start { perWeek[start, default: 0] += 1 }
        }
        var streak = (perWeek[thisWeek] ?? 0) >= planned ? 1 : 0
        var week = thisWeek
        while let previous = calendar.date(byAdding: .weekOfYear, value: -1, to: week),
              (perWeek[previous] ?? 0) >= planned {
            streak += 1
            week = previous
        }
        return streak
    }
}

/// A suggested change to the daily calorie target, from the weight trend. Always the user's choice to apply.
public struct CalorieAdvice: Equatable, Sendable {
    public enum Kind: String, Sendable { case adjust, hold, needMoreData }
    public var kind: Kind
    /// Change in kcal a day (0 unless `kind` is adjust).
    public var delta: Int
    public var newCalories: Int
    public var message: String
}

public enum CalorieCoach {
    public static let step = 100
    public static let minimumSpanDays = 14.0
    public static let minimumLoggedDays = 8
    public static let waitDaysAfterChange = 14.0

    /// - weeklyChangeKg: kg a week from `WeightTrend.weeklyChange`, nil if there aren't enough weigh-ins.
    /// - spanDays: days between the first and last weigh-in used.
    /// - loggedDays / averageIntake: food logging over the last 14 days.
    /// - daysSinceLastChange: days since the target was last changed by this coach or a goal change, if known.
    public static func advise(goal: Goal, currentCalories: Int, floor: Int, bodyWeightKg: Double,
                              weeklyChangeKg: Double?, spanDays: Double, loggedDays: Int, averageIntake: Double?,
                              easingIn: Bool, daysSinceLastChange: Double?) -> CalorieAdvice {
        func hold(_ kind: CalorieAdvice.Kind, _ text: String) -> CalorieAdvice {
            CalorieAdvice(kind: kind, delta: 0, newCalories: currentCalories, message: text)
        }
        if easingIn {
            return hold(.hold, "You're in your two weeks at maintenance. Suggestions start once your goal targets begin.")
        }
        if let d = daysSinceLastChange, d < waitDaysAfterChange {
            return hold(.hold, "Your target changed recently. Give it two weeks before judging it.")
        }
        guard let rate = weeklyChangeKg, spanDays >= minimumSpanDays, bodyWeightKg > 0 else {
            return hold(.needMoreData, "Log your weight at a few check-ins over at least two weeks and a suggestion will appear here.")
        }
        guard loggedDays >= minimumLoggedDays, let intake = averageIntake else {
            return hold(.needMoreData, "Log food on at least \(minimumLoggedDays) of the last 14 days so the suggestion is based on what you actually eat.")
        }
        let target = Double(currentCalories)
        if abs(intake - target) > target * 0.10 {
            let diff = Int(abs(intake - target).rounded())
            return hold(.hold, "You're averaging \(diff) kcal \(intake > target ? "over" : "under") your target, so the target isn't the thing to change yet.")
        }

        let pct = rate / bodyWeightKg * 100          // % of body weight a week
        let rateText = String(format: "%.1f", abs(rate))
        let direction = rate < 0 ? "down" : "up"
        var delta = 0
        var why = ""
        switch goal {
        case .fatLoss:
            if pct > -0.25 {
                delta = -step
                why = "Your weight is \(abs(rate) < 0.05 ? "steady" : "\(direction) about \(rateText) kg a week"), slower than a typical fat-loss pace."
            } else if pct < -1.0 {
                delta = step
                why = "You're losing about \(rateText) kg a week, faster than most people can sustain while keeping muscle."
            }
        case .buildMuscle:
            if pct < 0.1 {
                delta = step
                why = "Your weight is \(abs(rate) < 0.05 ? "steady" : "\(direction) about \(rateText) kg a week"), slower than a typical building pace."
            } else if pct > 0.5 {
                delta = -step
                why = "You're gaining about \(rateText) kg a week, faster than muscle is usually built."
            }
        case .maintain, .generalHealth:
            if pct > 0.5 {
                delta = -step
                why = "Your weight is drifting up about \(rateText) kg a week."
            } else if pct < -0.5 {
                delta = step
                why = "Your weight is drifting down about \(rateText) kg a week."
            }
        }
        if delta == 0 {
            return hold(.hold, "Your weight trend fits your goal. Keep your target as it is.")
        }
        let proposed = currentCalories + delta
        if proposed < floor {
            return hold(.hold, why + " Your target is already at the lowest daily amount this app sets, so it stays where it is.")
        }
        return CalorieAdvice(kind: .adjust, delta: delta, newCalories: proposed,
                             message: why + " A small step of \(delta > 0 ? "+" : "-")\(step) kcal a day is worth trying for two weeks.")
    }
}
