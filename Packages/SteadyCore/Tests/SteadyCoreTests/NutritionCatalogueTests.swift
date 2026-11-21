import XCTest
@testable import SteadyCore

final class NutritionCatalogueTests: XCTestCase {
    let entry = """
    {"country":"AU","category":"cafe","licence":"CC-BY-4.0","checkedOn":"2026-11-19","sourceURL":"https://example.com/menu",
     "item":{"id":"restaurant-serve-au-menu-oat-latte","name":"Oat latte","brand":"Example Café","servingGrams":100,
      "servingLabel":"One cup","per100":{"kcal":130,"protein":3,"carbs":16,"fat":6,"fibre":null}}}
    """

    func testDecodesAndSearchesAnOperatorSnapshot() throws {
        let catalogue = try makeCatalogue(entry)
        let food = try XCTUnwrap(catalogue.search("example latte").first)
        XCTAssertTrue(food.isPerServe)
        XCTAssertEqual(food.macros(grams: 200).kcal, 260)
        XCTAssertNil(food.per100.sodium)
        XCTAssertEqual(catalogue.entries.first?.checkedOn, "2026-11-19")
    }

    func testRejectsDuplicatesAndNonAustralianRows() {
        XCTAssertThrowsError(try makeCatalogue(entry + "," + entry))
        XCTAssertThrowsError(try makeCatalogue(entry.replacingOccurrences(of: "\"AU\"", with: "\"US\"")))
    }

    private func makeCatalogue(_ entries: String) throws -> NutritionCatalogue {
        try NutritionCatalogue(data: Data("{\"schemaVersion\":1,\"entries\":[\(entries)]}".utf8))
    }
}
