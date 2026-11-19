import Foundation

/// Searchable Australian operator data published after a catalogue review.
public struct NutritionCatalogue: Decodable, Sendable {
    public let schemaVersion: Int
    public let entries: [Entry]

    public init(data: Data) throws {
        let catalogue = try JSONDecoder().decode(Self.self, from: data)
        var ids = Set<String>()
        guard catalogue.schemaVersion == 1, catalogue.entries.allSatisfy({ entry in
            entry.isValid && ids.insert(entry.item.id).inserted
        }) else { throw CocoaError(.fileReadCorruptFile) }
        self = catalogue
    }

    public struct Entry: Decodable, Sendable {
        public let country: String
        public let category: String
        public let licence: String
        public let checkedOn: String
        public let sourceURL: URL
        public let item: FoodItem

        fileprivate var isValid: Bool {
            let prefix = item.isPerServe ? "restaurant-serve-au-menu-" : "au-menu-"
            let factor = item.isPerServe ? 10.0 : 1
            let nutrients = item.per100
            return country == "AU" && ["restaurant", "cafe", "coffee"].contains(category)
                && item.id.hasPrefix(prefix) && !item.name.isEmpty && !licence.isEmpty
                && sourceURL.scheme == "https" && sourceURL.host != nil
                && (0...950 * factor).contains(nutrients.kcal)
                && [nutrients.protein, nutrients.carbs, nutrients.fat, nutrients.fibre,
                    nutrients.sugar ?? 0, nutrients.satFat ?? 0].allSatisfy { (0...100 * factor).contains($0) }
                && (0...40_000 * factor).contains(nutrients.sodium ?? 0)
                && (0.001...10_000).contains(item.defaultGrams)
        }

        private enum CodingKeys: String, CodingKey {
            case country, category, licence, checkedOn, sourceURL, item
        }

        // Upstream leaves unreported fibre blank. The diary's existing totals use zero
        // contribution for an unreported value, while the original JSON retains the blank.
        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            country = try container.decode(String.self, forKey: .country)
            category = try container.decode(String.self, forKey: .category)
            licence = try container.decode(String.self, forKey: .licence)
            checkedOn = try container.decode(String.self, forKey: .checkedOn)
            sourceURL = try container.decode(URL.self, forKey: .sourceURL)
            let payload = try container.decode(EntryFood.self, forKey: .item)
            item = payload.food()
        }
    }

    public func search(_ query: String) -> [FoodItem] {
        let words = query.split(whereSeparator: \.isWhitespace)
        guard !words.isEmpty else { return [] }
        return entries.lazy.filter { row in
            let text = [row.item.name, row.item.brand ?? "", row.category].joined(separator: " ")
            return words.allSatisfy { text.localizedCaseInsensitiveContains(String($0)) }
        }.prefix(40).map(\.item)
    }

    private struct EntryFood: Decodable {
        let id: String
        let name: String
        let brand: String?
        let servingGrams: Double?
        let servingLabel: String?
        let amountUnit: String?
        let per100: Nutrients

        func food() -> FoodItem {
            let macros = Per100(kcal: per100.kcal, protein: per100.protein, carbs: per100.carbs, fat: per100.fat,
                                fibre: per100.fibre ?? 0, sugar: per100.sugar, satFat: per100.satFat, sodium: per100.sodium)
            return FoodItem(id: id, name: name, brand: brand, barcode: nil, per100: macros,
                            servingGrams: servingGrams, servingLabel: servingLabel, amountUnit: amountUnit)
        }
    }

    private struct Nutrients: Decodable {
        let kcal: Double
        let protein: Double
        let carbs: Double
        let fat: Double
        let fibre: Double?
        let sugar: Double?
        let satFat: Double?
        let sodium: Double?
    }
}
