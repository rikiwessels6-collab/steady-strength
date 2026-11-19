import Foundation

/// What was read from a photo of a nutrition information panel. Always shown to the user to check.
public struct PanelReading: Equatable, Sendable {
    public var kcal: Double?
    public var protein: Double?
    public var carbs: Double?
    public var fat: Double?
    public var fibre: Double?
    public var servingGrams: Double?
    /// Detail rows, when the panel has them: grams of sugars and saturated fat, milligrams of sodium.
    public var sugar: Double?
    public var satFat: Double?
    public var sodium: Double?
    /// True when the panel had a per-serve and a per-100 g column, so the per-100 g one could be picked out.
    public var foundBothColumns = false
    public var amountUnit: String?
    public var hasConfirmedBasis = false

    public var foundAnything: Bool { [kcal, protein, carbs, fat, fibre, sugar, satFat, sodium].contains { $0 != nil } }
}

/// Reads an Australian-style panel from lines of text (one line per table row), using the per 100 g column.
public enum NutritionPanel {
    public static func parse(_ rows: [String]) -> PanelReading {
        let lines = rows.map(normalise)
        var reading = PanelReading()

        let header = lines.first { $0.range(of: #"per\s*100\s*(?:ml|g)\b"#, options: .regularExpression) != nil }
        let per100 = header?.range(of: #"per\s*100\s*(?:ml|g)\b"#, options: .regularExpression)
        let perServe = #"per\s*(?:(?:serving|serve|portion)\b)"#
        var dual = false
        var per100First = false
        if let header, let per100 {
            let serveColumn = header.range(of: perServe, options: .regularExpression)
            dual = serveColumn != nil
            per100First = serveColumn.map { per100.lowerBound < $0.lowerBound } ?? true
            reading.amountUnit = header[per100].hasSuffix("ml") ? "mL" : "g"
        }
        let servingLine = lines.first { $0.contains("serving size") || $0.contains("serve size") || $0.contains("serv size") }
        let serveUnit = servingLine?.range(of: #"\d\s*ml\b"#, options: .regularExpression) != nil ? "mL" : "g"
        let servingAmount = servingLine.flatMap { numbers($0, units: ["g", "ml"]).first }.flatMap { $0 > 0 ? $0 : nil }
        if reading.amountUnit == nil || reading.amountUnit == serveUnit { reading.servingGrams = servingAmount }

        let serveOnly = header == nil && lines.contains {
            !$0.contains("package") && !$0.contains("container") && $0 != servingLine
                && $0.range(of: perServe, options: .regularExpression) != nil
        }
        // A declared per-serve column is safe to scale only with a readable serving size.
        if serveOnly && servingAmount == nil { return reading }
        if serveOnly { reading.amountUnit = serveUnit }
        reading.hasConfirmedBasis = header != nil || serveOnly
        var both = false
        let multiplier = serveOnly ? 100 / (servingAmount ?? 100) : 1
        func pick(_ values: [Double]) -> Double? {
            if dual && values.count != 2 { return nil }
            if !dual && (header != nil || serveOnly) && values.count != 1 { return nil }
            if dual { both = true }
            return (per100First ? values.first : values.last).map { $0 * multiplier }
        }

        var kj: [Double] = [], cal: [Double] = []
        for l in lines {
            if l == servingLine { continue }
            if l.contains("energy") || l.hasPrefix("kj") || l.hasPrefix("calories") {
                let newKj = numbers(l, units: ["kj"])
                let newCal = numbers(l, units: ["kcal", "cal", "calories"])
                if !newKj.isEmpty { kj = newKj }
                if !newCal.isEmpty { cal = newCal }
                if newCal.isEmpty, !dual, l.hasPrefix("calories"),
                   let value = Double(l.dropFirst("calories".count).trimmingCharacters(in: CharacterSet(charactersIn: " :"))) {
                    cal = [value]
                }
                continue
            }
            if l.contains("sugar") && !l.contains("carbohydrate") {
                if reading.sugar == nil { reading.sugar = pick(numbers(l, units: ["g"])) }
                continue
            }
            if l.contains("sodium") {
                if reading.sodium == nil {
                    reading.sodium = pick(numbers(l, units: ["mg", "g"], asMilligrams: true))
                }
                continue
            }
            if l.contains("saturated") && !l.contains("unsat") && !l.contains("trans") {
                if reading.satFat == nil { reading.satFat = pick(numbers(l, units: ["g"])) }
                continue
            }
            let isSub = l.hasPrefix("-") || l.hasPrefix("•") || l.contains("saturated") || l.contains("trans")
                || l.contains("polyunsat") || l.contains("monounsat") || l.contains("omega")
            if l.contains("protein") {
                if reading.protein == nil { reading.protein = pick(numbers(l, units: ["g"])) }
            } else if l.contains("fibre") || l.contains("fiber") {
                if reading.fibre == nil { reading.fibre = pick(numbers(l, units: ["g"])) }
            } else if l.contains("carbohydrate") || l.contains("carbs") {
                if reading.carbs == nil, !isSub { reading.carbs = pick(numbers(l, units: ["g"])) }
            } else if l.contains("sugar") || l.contains("sodium") || l.contains("salt") {
                continue
            } else if l.contains("fat") {
                if reading.fat == nil, !isSub { reading.fat = pick(numbers(l, units: ["g"])) }
            }
        }
        if let c = pick(cal), (0...950).contains(c) {
            reading.kcal = c
        } else if let k = pick(kj) {
            reading.kcal = (k / 4.184).rounded()
        }
        reading.foundBothColumns = both
        // A per-100 g value can't be more than 100 g, and food has at most about 900 kcal per 100 g.
        if let k = reading.kcal, k > 950 { reading.kcal = nil }
        if let p = reading.protein, p > 100 { reading.protein = nil }
        if let c = reading.carbs, c > 100 { reading.carbs = nil }
        if let f = reading.fat, f > 100 { reading.fat = nil }
        if let f = reading.fibre, f > 100 { reading.fibre = nil }
        if let x = reading.sugar, x > 100 { reading.sugar = nil }
        if let x = reading.satFat, x > 100 { reading.satFat = nil }
        if let x = reading.sodium, x > 40_000 { reading.sodium = nil }
        return reading
    }

    private static func normalise(_ s: String) -> String {
        var t = s.lowercased()
        // "6,0 g" is a decimal comma.
        t = t.replacingOccurrences(of: #"(\d),(\d)"#, with: "$1.$2", options: .regularExpression)
        return t.trimmingCharacters(in: .whitespaces)
    }

    /// Numbers directly followed by one of the units, in the order they appear ("<1 g" gives 1).
    static func numbers(_ line: String, units: [String], asMilligrams: Bool = false) -> [Double] {
        let pattern = #"(?<![\d.,-])(\d+(?:\.\d+)?)\s*("# + units.joined(separator: "|") + #")(?![a-z])"#
        guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(line.startIndex..., in: line)
        return re.matches(in: line, range: range).compactMap { m in
            guard let digits = Range(m.range(at: 1), in: line), let value = Double(line[digits]),
                  let unit = Range(m.range(at: 2), in: line) else { return nil }
            return asMilligrams && line[unit] == "g" ? value * 1000 : value
        }
    }
}
