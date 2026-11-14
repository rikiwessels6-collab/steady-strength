import Foundation

/// One ingredient as weighed into a recipe, with its macros for that amount.
public struct RecipeIngredient: Codable, Equatable, Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var grams: Double
    public var kcal: Double
    public var protein: Double
    public var carbs: Double
    public var fat: Double
    public var fibre: Double

    public init(id: String = UUID().uuidString, name: String, grams: Double, kcal: Double, protein: Double,
                carbs: Double, fat: Double, fibre: Double = 0) {
        self.id = id; self.name = name; self.grams = grams; self.kcal = kcal
        self.protein = protein; self.carbs = carbs; self.fat = fat; self.fibre = fibre
    }

    /// From a food and a weighed amount.
    public init(food: FoodItem, grams: Double) {
        let m = food.macros(grams: grams)
        self.init(name: food.name, grams: grams, kcal: m.kcal, protein: m.protein, carbs: m.carbs, fat: m.fat, fibre: m.fibre)
    }
}

/// Home-cooked dishes: add up the raw ingredients, then share the total across servings or the cooked weight.
public enum RecipeMath {
    public static func totals(_ items: [RecipeIngredient]) -> Macros {
        items.reduce(Macros()) { $0 + Macros(kcal: $1.kcal, protein: $1.protein, carbs: $1.carbs, fat: $1.fat, fibre: $1.fibre) }
    }

    /// The finished dish's weight: the cooked weight if it was weighed (water is lost or gained in cooking),
    /// otherwise the raw ingredients added up.
    public static func totalWeight(_ items: [RecipeIngredient], cookedWeight: Double?) -> Double {
        if let c = cookedWeight, c > 0 { return c }
        return items.reduce(0) { $0 + $1.grams }
    }

    public static func per100(_ items: [RecipeIngredient], cookedWeight: Double?) -> Per100 {
        let weight = totalWeight(items, cookedWeight: cookedWeight)
        guard weight > 0 else { return Per100(kcal: 0, protein: 0, carbs: 0, fat: 0) }
        let t = totals(items)
        let f = 100 / weight
        return Per100(kcal: t.kcal * f, protein: t.protein * f, carbs: t.carbs * f, fat: t.fat * f, fibre: t.fibre * f)
    }

    /// Grams on the plate for a number of servings, when the dish makes `servingsInRecipe`.
    public static func grams(servings: Double, servingsInRecipe: Double, totalWeight: Double) -> Double {
        guard servingsInRecipe > 0 else { return 0 }
        return totalWeight / servingsInRecipe * servings
    }
}
