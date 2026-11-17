import Foundation

/// Everyday unbranded foods from AUSNUT 2023 (Food Standards Australia New Zealand, CC BY 4.0),
/// bundled with the app so they work offline. Values per 100 g, copied as published.
public struct GenericFoods: Decodable, Sendable {
    public struct Food: Decodable, Sendable, Identifiable {
        public let id: String
        public let name: String
        public let kj: Double
        public let p: Double
        public let f: Double
        public let c: Double
        public let fi: Double
        public let su: Double?
        public let sf: Double?
        public let na: Double?
        public let measures: [FoodMeasure]?
        /// Grams per millilitre, as published, for converting a volume to a weight.
        public let density: Double?
    }

    public static let idPrefix = "ausnut-"
    public static let brand = "Generic · AUSNUT 2023"

    public let source: String
    public let checkedOn: String?
    public let foods: [Food]
    private let lowered: [String]
    private let byId: [String: Int]

    enum CodingKeys: String, CodingKey { case source, checkedOn, foods }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        source = try c.decode(String.self, forKey: .source)
        checkedOn = try c.decodeIfPresent(String.self, forKey: .checkedOn)
        foods = try c.decode([Food].self, forKey: .foods)
        lowered = foods.map { $0.name.lowercased() }
        byId = Dictionary(foods.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { a, _ in a })
    }

    /// A food by its AUSNUT public food key, e.g. "F005634".
    public func food(id: String) -> Food? { byId[id].map { foods[$0] } }

    public init(data: Data) throws { self = try JSONDecoder().decode(GenericFoods.self, from: data) }

    /// Foods whose name has every word typed (a plural also matches its singular),
    /// best first: names that start with the first word, then shorter names.
    public func search(_ query: String, limit: Int = 25) -> [FoodItem] {
        let words = query.lowercased().split(whereSeparator: { $0 == " " || $0 == "," }).map(String.init)
        guard !words.isEmpty else { return [] }
        func has(_ name: String, _ w: String) -> Bool {
            if name.contains(w) { return true }
            if w.count > 3, w.hasSuffix("es"), name.contains(w.dropLast(2)) { return true }
            if w.count > 3, w.hasSuffix("s"), name.contains(w.dropLast()) { return true }
            return false
        }
        var hits: [(score: Int, index: Int)] = []
        for (i, name) in lowered.enumerated() where words.allSatisfy({ has(name, $0) }) {
            let first = words[0]
            let lead = name.hasPrefix(first) || name.hasPrefix(String(first.dropLast())) ? 0 : 1000
            hits.append((score: lead + name.count, index: i))
        }
        return hits.sorted { $0.score != $1.score ? $0.score < $1.score : $0.index < $1.index }
            .prefix(limit).map { item(foods[$0.index]) }
    }

    public func item(_ f: Food) -> FoodItem {
        let per = Per100(kcal: f.kj / 4.184, protein: f.p, carbs: f.c, fat: f.f, fibre: f.fi,
                         sugar: f.su, satFat: f.sf, sodium: f.na)
        let first = f.measures?.first
        return FoodItem(id: Self.idPrefix + f.id, name: f.name, brand: Self.brand, barcode: nil, per100: per,
                        servingGrams: first?.grams, servingLabel: first?.label, measures: f.measures)
    }
}
