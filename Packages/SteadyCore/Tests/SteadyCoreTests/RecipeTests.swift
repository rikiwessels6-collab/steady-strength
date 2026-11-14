import XCTest
@testable import SteadyCore

final class RecipeTests: XCTestCase {
    private let mince = RecipeIngredient(name: "Beef mince", grams: 500, kcal: 1250, protein: 100, carbs: 0, fat: 90)
    private let pasta = RecipeIngredient(name: "Pasta", grams: 400, kcal: 1400, protein: 50, carbs: 280, fat: 6, fibre: 12)

    func testTotalsAddUp() {
        let t = RecipeMath.totals([mince, pasta])
        XCTAssertEqual(t.kcal, 2650)
        XCTAssertEqual(t.protein, 150)
        XCTAssertEqual(t.fibre, 12)
    }

    func testCookedWeightWinsOverRawWeight() {
        XCTAssertEqual(RecipeMath.totalWeight([mince, pasta], cookedWeight: nil), 900)
        XCTAssertEqual(RecipeMath.totalWeight([mince, pasta], cookedWeight: 1325), 1325)
        XCTAssertEqual(RecipeMath.totalWeight([mince, pasta], cookedWeight: 0), 900)
        let p = RecipeMath.per100([mince, pasta], cookedWeight: 1325)
        XCTAssertEqual(p.kcal, 200, accuracy: 0.01)
    }

    func testServingsToGrams() {
        XCTAssertEqual(RecipeMath.grams(servings: 1, servingsInRecipe: 4, totalWeight: 1200), 300)
        XCTAssertEqual(RecipeMath.grams(servings: 1.5, servingsInRecipe: 4, totalWeight: 1200), 450)
        XCTAssertEqual(RecipeMath.grams(servings: 1, servingsInRecipe: 0, totalWeight: 1200), 0)
        // One serving's macros come out as a quarter of the dish.
        let per100 = RecipeMath.per100([mince, pasta], cookedWeight: 1200)
        let item = FoodItem(id: "r", name: "Bolognese", brand: nil, barcode: nil, per100: per100, servingGrams: 300, servingLabel: nil)
        XCTAssertEqual(item.macros(grams: 300).kcal, 2650 / 4, accuracy: 0.01)
    }

    func testIngredientFromFood() {
        let oats = FoodItem(id: "oats", name: "Oats", brand: nil, barcode: nil,
                            per100: Per100(kcal: 380, protein: 13, carbs: 60, fat: 7), servingGrams: nil, servingLabel: nil)
        let i = RecipeIngredient(food: oats, grams: 50)
        XCTAssertEqual(i.kcal, 190, accuracy: 0.01)
        XCTAssertEqual(i.grams, 50)
    }

    func testEmptyRecipeIsSafe() {
        XCTAssertEqual(RecipeMath.per100([], cookedWeight: nil).kcal, 0)
    }
}
