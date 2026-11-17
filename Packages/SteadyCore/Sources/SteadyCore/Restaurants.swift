import Foundation

/// Restaurant and takeaway menus, bundled with the app (Resources/Restaurants/restaurants.json).
/// Every value is copied from the chain's own published nutrition guide.
public struct RestaurantMenus: Decodable, Sendable {
    public let chains: [RestaurantChain]

    public init(data: Data) throws {
        self = try JSONDecoder().decode(RestaurantMenus.self, from: data)
    }

    /// Items whose name or chain matches every word typed, for food search.
    public func search(_ query: String) -> [(chain: RestaurantChain, item: RestaurantItem)] {
        let words = query.lowercased().split(separator: " ").map(String.init)
        guard !words.isEmpty else { return [] }
        return chains.flatMap { chain in
            chain.items.filter { item in
                let text = (chain.name + " " + item.name + " " + item.category).lowercased()
                return words.allSatisfy { text.contains($0) }
            }.map { (chain, $0) }
        }
    }
}

extension FoodItem {
    /// Foods logged by the serve: their "per 100" values are for one serve, and 100 means one serve.
    public static let perServePrefix = "restaurant-serve-"
    public var isPerServe: Bool { id.hasPrefix(Self.perServePrefix) }
}

public struct RestaurantChain: Decodable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let items: [RestaurantItem]

    /// Where this chain's numbers come from, with the date checked, for display.
    public var sources: [String] {
        var seen: [String] = []
        for i in items {
            let line = i.source + (i.checkedOn.map { " Checked \($0)." } ?? "")
            if !seen.contains(line) { seen.append(line) }
        }
        return seen
    }

    /// Categories in the order they first appear.
    public var categories: [String] {
        var seen: [String] = []
        for i in items where !seen.contains(i.category) { seen.append(i.category) }
        return seen
    }
}

public struct RestaurantItem: Decodable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let category: String
    /// One serve, in grams or millilitres. Nil when the guide gives no weight; then `unit` is "serve".
    public let serveAmount: Double?
    public let unit: String
    /// What one serve is, when there is no weight, e.g. "1 standard burger".
    public let servingDescription: String?
    /// When the values were last checked against the source.
    public let checkedOn: String?
    public let kj: Double
    public let kcal: Double
    public let protein: Double
    public let fat: Double
    public let satFat: Double?
    public let carbs: Double
    public let sugar: Double?
    public let sodium: Double?
    public let source: String
    public let note: String?

    /// True when the item is logged by the serve because the guide gives no weight.
    public var isPerServe: Bool { (serveAmount ?? 0) <= 0 || unit == "serve" }

    /// As a food to log. With a weight: per-100 values worked out from one serve, one serve as the default amount.
    /// Without one: the food's "100" is one serve (its id says so, see FoodItem.isPerServe), so nothing is invented.
    public func food(chain: RestaurantChain) -> FoodItem {
        let f: Double
        let serving: Double
        let label: String
        if isPerServe {
            f = 1; serving = 100; label = servingDescription ?? "1 serve"
        } else {
            let amount = serveAmount ?? 100
            f = 100 / amount; serving = amount; label = "1 serve (\(Int(amount.rounded())) \(unit))"
        }
        return FoodItem(id: (isPerServe ? FoodItem.perServePrefix : "restaurant-") + id, name: name, brand: chain.name, barcode: nil,
                        per100: Per100(kcal: kcal * f, protein: protein * f, carbs: carbs * f, fat: fat * f, fibre: 0,
                                       sugar: sugar.map { $0 * f }, satFat: satFat.map { $0 * f }, sodium: sodium.map { $0 * f }),
                        servingGrams: serving, servingLabel: label)
    }
}
