import XCTest
@testable import SteadyCore

final class MealTextTests: XCTestCase {
    func testParsesAnEverydayMeal() {
        let lines = MealText.parse("2 eggs, 2 slices of sourdough and a flat white")
        XCTAssertEqual(lines.map(\.name), ["eggs", "sourdough", "flat white"])
        XCTAssertEqual(lines.map(\.quantity), [2, 2, 1])
        XCTAssertEqual(lines.map(\.unit), [.portion, .slice, .portion])
    }

    func testParsesUnitsAndFractionsWithoutSplittingDishNames() {
        let lines = MealText.parse("125g chicken; 1 1/2 cups of rice\nhalf a cup of milk and fish and chips")
        XCTAssertEqual(lines.map(\.name), ["chicken", "rice", "milk", "fish & chips"])
        XCTAssertEqual(lines.map(\.quantity), [125, 1.5, 0.5, 1])
        XCTAssertEqual(lines.map(\.unit), [.gram, .cup, .cup, .portion])
        XCTAssertEqual(MealText.parse("1½ serves of pumpkin")[0].quantity, 1.5)
    }

    func testParsesDetailedEverydayLunchIntoReviewableFoods() {
        let lines = MealText.parse("2 slices of white bread, avocado spread on both slices and diced chicken breast")
        XCTAssertEqual(lines.map(\.name), ["white bread", "avocado spread on both slices", "diced chicken breast"])
        XCTAssertEqual(lines.map(\.quantity), [2, 1, 1])
        XCTAssertEqual(lines.map(\.unit), [.slice, .portion, .portion])
    }

    func testPortionsRequireACompatibleUnitOrARealMeasure() throws {
        let bread = FoodItem(id: "bread", name: "Bread", brand: nil, barcode: nil,
                            per100: Per100(kcal: 200, protein: 8, carbs: 40, fat: 2),
                            servingGrams: 34, servingLabel: "1 slice",
                            measures: [FoodMeasure(label: "1 slice", grams: 34)])
        let slices = try XCTUnwrap(MealText.parse("2 slices of bread").first)
        XCTAssertEqual(slices.portion(for: bread)?.amount, 68)
        let cups = try XCTUnwrap(MealText.parse("2 cups of bread").first)
        XCTAssertNil(cups.portion(for: bread))
        let volume = try XCTUnwrap(MealText.parse("200 mL bread").first)
        XCTAssertNil(volume.portion(for: bread))
        var milk = bread
        milk.amountUnit = "mL"
        let litre = try XCTUnwrap(MealText.parse("0.25 L milk").first)
        XCTAssertEqual(litre.portion(for: milk)?.amount, 250)
    }

    func testSingleCountDoesNotInventAServe() throws {
        let food = FoodItem(id: "rice", name: "Rice", brand: nil, barcode: nil,
                            per100: Per100(kcal: 135, protein: 2, carbs: 31, fat: 0),
                            servingGrams: nil, servingLabel: nil)
        let count = try XCTUnwrap(MealText.parse("2 rice").first)
        XCTAssertNil(count.portion(for: food))
        let weighed = try XCTUnwrap(MealText.parse("150 g rice").first)
        XCTAssertEqual(weighed.portion(for: food)?.amount, 150)
    }

    func testGenericIngredientSuggestionsUseUsefulEditableStartingWeights() throws {
        let avocado = FoodItem(id: "ausnut-F000162", name: "Avocado, raw", brand: GenericFoods.brand,
                               barcode: nil, per100: Per100(kcal: 160, protein: 2, carbs: 1, fat: 15),
                               servingGrams: nil, servingLabel: nil)
        let chicken = FoodItem(id: "ausnut-F002592", name: "Chicken, breast, lean, cooked", brand: GenericFoods.brand,
                               barcode: nil, per100: Per100(kcal: 150, protein: 30, carbs: 0, fat: 3),
                               servingGrams: nil, servingLabel: nil)
        XCTAssertEqual(try XCTUnwrap(MealText.parse("avocado").first).suggestedGenericGrams(for: avocado), 50)
        XCTAssertEqual(try XCTUnwrap(MealText.parse("diced chicken breast").first).suggestedGenericGrams(for: chicken), 100)
    }
}
