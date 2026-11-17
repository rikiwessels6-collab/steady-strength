import Foundation

extension FoodItem {
    /// Energy for a list row: per serve when the food has a serve, otherwise per 100 g.
    /// Foods logged by the serve store one serve as "100", so their value is already per serve.
    public var energyLabel: String {
        if isPerServe { return "\(Int(per100.kcal.rounded())) kcal/serve" }
        if let g = servingGrams, g > 0 { return "\(Int((per100.kcal * g / 100).rounded())) kcal/serve" }
        return "\(Int(per100.kcal.rounded())) kcal/100g"
    }

    /// The serve a row describes, e.g. "serve 1 slice (35 g)".
    public var serveText: String? {
        if isPerServe { return servingLabel.map { "serve: \($0)" } ?? "per serve" }
        guard let g = servingGrams, g > 0 else { return nil }
        let grams = "\(NumberText.format((g * 10).rounded() / 10)) g"
        let base = servingLabel.map { $0.contains("(") ? $0 : "\($0) (\(grams))" } ?? grams
        return base.hasPrefix("1 serve") ? base : "serve " + base
    }
}

public enum FoodRanking {
    /// Best matches first: the name starts with what was typed, then a word in the name starts with it,
    /// then everything else. Ties keep their original order (so database ranking survives).
    public static func rank(_ items: [FoodItem], query: String) -> [FoodItem] {
        let q = query.lowercased().trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return items }
        let first = q.split(separator: " ").first.map(String.init) ?? q
        func score(_ item: FoodItem) -> Int {
            let name = item.name.lowercased()
            if name.hasPrefix(q) { return 0 }
            let words = name.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            if words.contains(where: { $0.hasPrefix(first) }) { return 1 }
            return 2
        }
        return items.enumerated()
            .sorted { (a, b) in
                let sa = score(a.element), sb = score(b.element)
                return sa != sb ? sa < sb : a.offset < b.offset
            }
            .map(\.element)
    }
}
