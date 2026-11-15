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

public struct RestaurantChain: Decodable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let items: [RestaurantItem]

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
    /// One serve, in grams or millilitres.
    public let serveAmount: Double
    public let unit: String
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

    /// As a food to log: per-100 values worked out from one serve, with one serve as the default amount.
    public func food(chain: RestaurantChain) -> FoodItem {
        let f = serveAmount > 0 ? 100 / serveAmount : 0
        return FoodItem(id: "restaurant-" + id, name: name, brand: chain.name, barcode: nil,
                        per100: Per100(kcal: kcal * f, protein: protein * f, carbs: carbs * f, fat: fat * f, fibre: 0,
                                       sugar: sugar.map { $0 * f }, satFat: satFat.map { $0 * f }, sodium: sodium.map { $0 * f }),
                        servingGrams: serveAmount, servingLabel: "1 serve (\(Int(serveAmount.rounded())) \(unit))")
    }
}
