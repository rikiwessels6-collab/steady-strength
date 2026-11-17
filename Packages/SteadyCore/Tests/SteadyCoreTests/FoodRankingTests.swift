import XCTest
@testable import SteadyCore

final class FoodRankingTests: XCTestCase {
    private func food(_ id: String, _ name: String, kcal: Double = 200, grams: Double? = nil, label: String? = nil) -> FoodItem {
        FoodItem(id: id, name: name, brand: nil, barcode: nil, per100: Per100(kcal: kcal, protein: 0, carbs: 0, fat: 0),
                 servingGrams: grams, servingLabel: label)
    }

    func testNamesStartingWithTheQueryComeFirst() {
        let items = [food("a", "Pizza, chicken"), food("b", "Bowl, Chicken O.G."), food("c", "Chicken breast, grilled"), food("d", "Crispy wonton")]
        XCTAssertEqual(FoodRanking.rank(items, query: "chicken").map(\.id), ["c", "a", "b", "d"])
    }

    func testEnergyLabelPerServeOrPer100() {
        XCTAssertEqual(food("x", "Oats").energyLabel, "200 kcal/100g")
        XCTAssertEqual(food("x", "Bread", grams: 35, label: "1 slice").energyLabel, "70 kcal/serve")
        XCTAssertEqual(food("x", "Bread", grams: 35, label: "1 slice").serveText, "serve 1 slice (35 g)")
        XCTAssertEqual(food("x", "Burrito", grams: 480, label: "1 serve (480 g)").serveText, "1 serve (480 g)")
        let burger = food(FoodItem.perServePrefix + "big-mac", "Big Mac", kcal: 559, grams: 100, label: "1 standard burger")
        XCTAssertEqual(burger.energyLabel, "559 kcal/serve")
        XCTAssertEqual(burger.serveText, "serve: 1 standard burger")
    }
}
