import Foundation

/// Recognises a short list of foods and portions locally. A match is always reviewed before logging.
public enum MealText {
    public enum Unit: String, Equatable, Sendable {
        case portion, gram, kilogram, millilitre, litre, slice, cup, teaspoon, tablespoon, serving, piece

        fileprivate static let terms: [String: Self] = [
            "g": .gram, "gram": .gram, "grams": .gram, "kg": .kilogram, "kilogram": .kilogram, "kilograms": .kilogram,
            "ml": .millilitre, "millilitre": .millilitre, "millilitres": .millilitre,
            "l": .litre, "litre": .litre, "litres": .litre,
            "slice": .slice, "slices": .slice, "cup": .cup, "cups": .cup,
            "tsp": .teaspoon, "teaspoon": .teaspoon, "teaspoons": .teaspoon,
            "tbsp": .tablespoon, "tablespoon": .tablespoon, "tablespoons": .tablespoon,
            "serve": .serving, "serves": .serving, "serving": .serving, "servings": .serving,
            "piece": .piece, "pieces": .piece,
        ]
    }

    public struct Line: Equatable, Sendable {
        public let name: String
        public let quantity: Double
        public let unit: Unit

        public struct Portion: Equatable, Sendable {
            public let measure: FoodMeasure?
            /// The number to show in the quantity field, in portions, grams or millilitres.
            public let quantity: Double
            public var amount: Double? {
                if let measure { return measure.amount(for: quantity) }
                return quantity.isFinite && quantity > 0 ? quantity : nil
            }
        }

        /// Only convert when a matching measure or compatible nutrition unit is known.
        public func portion(for food: FoodItem) -> Portion? {
            switch unit {
            case .gram, .kilogram:
                guard !food.isPerServe, food.portionUnit == "g" else { return nil }
                return Portion(measure: nil, quantity: quantity * (unit == .kilogram ? 1_000 : 1))
            case .millilitre, .litre:
                guard !food.isPerServe, food.portionUnit == "mL" else { return nil }
                return Portion(measure: nil, quantity: quantity * (unit == .litre ? 1_000 : 1))
            case .portion, .serving:
                guard let measure = food.defaultQuantityMeasure else { return nil }
                return Portion(measure: measure, quantity: quantity)
            case .slice, .cup, .teaspoon, .tablespoon, .piece:
                let measure = food.quantityMeasures.first { candidate in
                    candidate.label.lowercased().split(whereSeparator: { !$0.isLetter }).contains { word in
                        Unit.terms[String(word)] == unit
                    }
                }
                guard let measure else { return nil }
                return Portion(measure: measure, quantity: quantity)
            }
        }

        /// A practical starting weight when someone describes an everyday food
        /// without specifying an amount. This is deliberately only used for the
        /// bundled generic food database; branded and restaurant food must be
        /// selected with an actual serve or entered weight.
        public func suggestedGenericGrams(for food: FoodItem) -> Double? {
            guard unit == .portion,
                  food.id.hasPrefix(GenericFoods.idPrefix),
                  !food.isPerServe,
                  food.portionUnit == "g" else { return nil }

            let words = Set(MealText.searchTerms(name))
            if words.contains("avocado") { return 50 }
            if words.contains("chicken") && words.contains("breast") { return 100 }
            return 100
        }
    }

    private static let numbers: [String: Double] = [
        "a": 1, "an": 1, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5,
        "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10, "half": 0.5,
    ]
    private static let numberPrefix = #"^(\d+\s+\d+/\d+|\d+/\d+|\d+(?:\.\d+)?|a half|half(?: an?)?|a|an|one|two|three|four|five|six|seven|eight|nine|ten)(?=\s|$|(?<=\d)[a-z])"#
    private static let unitPrefix = #"^([a-z]+)\b"#

    public static func parse(_ text: String) -> [Line] {
        var text = text.replacingOccurrences(of: #"(\d)[ \t]*½"#, with: "$1.5", options: .regularExpression)
        text = text.replacingOccurrences(of: "½", with: "0.5")
        for name in ["fish and chips", "mac and cheese", "macaroni and cheese"] {
            text = text.replacingOccurrences(of: name, with: name.replacingOccurrences(of: " and ", with: " & "),
                                             options: .caseInsensitive)
        }
        let marked = text.replacingOccurrences(of: #"\s+\band\b\s+|[,;\n]"#, with: "\n",
                                              options: [.regularExpression, .caseInsensitive])
        return marked.split(separator: "\n").compactMap { parseLine(String($0)) }
    }

    private static func parseLine(_ raw: String) -> Line? {
        var name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        var quantity: Double = 1
        var unit: Unit = .portion
        if let range = name.range(of: numberPrefix, options: [.regularExpression, .caseInsensitive]) {
            let prefix = name[range].lowercased()
            let rest = name[range.upperBound...].trimmingCharacters(in: .whitespaces)
            if !rest.isEmpty, let number = parseNumber(prefix) {
                quantity = number
                name = rest
                if let unitRange = name.range(of: unitPrefix, options: [.regularExpression, .caseInsensitive]),
                   let found = Unit.terms[name[unitRange].lowercased()] {
                    let rest = name[unitRange.upperBound...].trimmingCharacters(in: .whitespaces)
                    if !rest.isEmpty {
                        unit = found
                        name = rest.replacingOccurrences(of: #"^of\s+"#, with: "", options: [.regularExpression, .caseInsensitive])
                    }
                }
            }
        }
        return Line(name: name, quantity: quantity, unit: unit)
    }

    private static func parseNumber(_ prefix: String) -> Double? {
        if prefix.contains("half") { return 0.5 }
        if let value = numbers[prefix] ?? Double(prefix) { return value }
        let parts = prefix.split(separator: " ")
        guard let fraction = parts.last else { return nil }
        let ratio = fraction.split(separator: "/")
        guard ratio.count == 2, let numerator = Double(ratio[0]), let denominator = Double(ratio[1]), denominator > 0 else { return nil }
        return (parts.count > 1 ? (Double(parts[0]) ?? 0) : 0) + numerator / denominator
    }

    /// Common inflections for matching natural language to catalogue descriptions.
    public static func searchTerms(_ name: String) -> [String] {
        name.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map { word in
            switch word {
            case "sandwiches": "sandwich"
            case "tomatoes": "tomato"
            case "potatoes": "potato"
            default: word.count > 3 && word.hasSuffix("s") && !word.hasSuffix("ss") ? String(word.dropLast()) : String(word)
            }
        }
    }
}
