import Foundation

/// What to load for the next set, judged from the set just done. Lighter is applied straight away
/// (it is always the safe direction); heavier is only offered, and the person taps to accept it.
public struct SetAdvice: Equatable, Sendable {
    public enum Kind: String, Sendable { case keep, lighter, heavier }
    public var kind: Kind
    public var weight: Double
    public var note: String?
}

public enum SetAdvisor {
    /// - step: the smallest change worth making for this exercise (kg).
    public static func next(lastWeight: Double, lastReps: Int, minReps: Int?, topReps: Int?, step: Double) -> SetAdvice {
        let keep = SetAdvice(kind: .keep, weight: lastWeight, note: nil)
        guard lastWeight > 0, step > 0, lastReps > 0, let lo = minReps, let hi = topReps, hi >= lo else { return keep }
        let range = lo == hi ? "\(lo)" : "\(lo)-\(hi)"
        if lastReps < lo {
            // Well short of the range: a bigger drop. Just short: a small one.
            let cut = (lo - lastReps) >= 3 ? 0.10 : 0.05
            var lighter = Progression.roundDown(lastWeight * (1 - cut), to: step)
            if lighter >= lastWeight { lighter = lastWeight - step }
            guard lighter > 0 else { return keep }
            return SetAdvice(kind: .lighter, weight: lighter,
                             note: "You got \(lastReps); the aim is \(range). Lighter for the next set so it lands in range.")
        }
        if lastReps >= hi + 3 {
            return SetAdvice(kind: .heavier, weight: lastWeight + step,
                             note: "\(lastReps) reps is well above \(range).")
        }
        return keep
    }
}

/// A short line for the rest timer: what comes after this rest.
public enum NextUp {
    /// - remaining: for each exercise in order, its name and how many sets are still to do.
    /// - current: index of the exercise just worked.
    public static func text(remaining: [(name: String, done: Int, total: Int)], current: Int) -> String? {
        guard remaining.indices.contains(current) else { return nil }
        let now = remaining[current]
        if now.done < now.total { return "Next: set \(now.done + 1) of \(now.total)" }
        if let next = remaining[(current + 1)...].first(where: { $0.done < $0.total }) { return "Next: \(next.name)" }
        if let earlier = remaining[..<current].first(where: { $0.done < $0.total }) { return "Next: \(earlier.name)" }
        return "That was your last set"
    }
}

/// Foods someone usually eats at a meal, for one-tap logging.
public struct UsualFood: Equatable, Sendable, Identifiable {
    public var foodId: String
    public var name: String
    public var grams: Double
    public var count: Int
    public var id: String { foodId }
}

public enum FoodHabits {
    public struct Eaten: Sendable {
        public var foodId: String
        public var name: String
        public var grams: Double
        public var date: Date
        public init(foodId: String, name: String, grams: Double, date: Date) {
            self.foodId = foodId; self.name = name; self.grams = grams; self.date = date
        }
    }

    /// Foods eaten at least twice in `history`, most often first (ties: most recent first), with the amount used
    /// last time. `excluding` leaves out foods already logged in the meal being viewed.
    public static func usual(_ history: [Eaten], excluding: Set<String> = [], limit: Int = 3) -> [UsualFood] {
        let groups = Dictionary(grouping: history.filter { !excluding.contains($0.foodId) }, by: \.foodId)
        return groups.compactMap { id, list -> (UsualFood, Date)? in
            guard list.count >= 2, let latest = list.max(by: { $0.date < $1.date }) else { return nil }
            return (UsualFood(foodId: id, name: latest.name, grams: latest.grams, count: list.count), latest.date)
        }
        .sorted { a, b in a.0.count != b.0.count ? a.0.count > b.0.count : a.1 > b.1 }
        .prefix(limit)
        .map(\.0)
    }
}
