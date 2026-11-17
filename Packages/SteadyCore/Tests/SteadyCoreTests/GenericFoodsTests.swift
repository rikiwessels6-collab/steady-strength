import XCTest
@testable import SteadyCore

final class GenericFoodsTests: XCTestCase {
    private let json = """
    {"source":"AUSNUT 2023, © Food Standards Australia New Zealand","checkedOn":"2026-11-17","foods":[
     {"id":"F1","name":"Egg, chicken, whole, boiled","kj":580,"p":12.6,"f":9.4,"c":0.6,"fi":0,"su":0.6,"sf":2.9,"na":130,
      "measures":[{"label":"1 egg, large","grams":51},{"label":"1 cup, chopped","grams":136}]},
     {"id":"F2","name":"Bread, white, commercial","kj":1030,"p":8.6,"f":2.4,"c":44,"fi":2.8},
     {"id":"F3","name":"Noodles, egg, boiled","kj":580,"p":4.5,"f":0.6,"c":25,"fi":1.2}
    ]}
    """

    private func foods() throws -> GenericFoods { try GenericFoods(data: Data(json.utf8)) }

    func testSearchMatchesEveryWordAndPlurals() throws {
        let g = try foods()
        XCTAssertEqual(g.search("eggs").map(\.name), ["Egg, chicken, whole, boiled", "Noodles, egg, boiled"])
        XCTAssertEqual(g.search("white bread").map(\.name), ["Bread, white, commercial"])
        XCTAssertTrue(g.search("pizza").isEmpty)
    }

    func testItemKeepsPublishedValuesAndPortions() throws {
        let egg = try foods().search("egg")[0]
        XCTAssertEqual(egg.id, "ausnut-F1")
        XCTAssertEqual(egg.per100.kcal, 580 / 4.184, accuracy: 0.001)
        XCTAssertEqual(egg.per100.sodium, 130)
        XCTAssertEqual(egg.servingGrams, 51)
        XCTAssertEqual(egg.servingLabel, "1 egg, large")
        XCTAssertEqual(egg.measures?.count, 2)
        XCTAssertEqual(egg.macros(grams: 51).protein, 12.6 * 0.51, accuracy: 0.001)
    }

    func testBlankDetailStaysUnknown() throws {
        let bread = try foods().search("bread")[0]
        XCTAssertNil(bread.per100.sugar)
        XCTAssertNil(bread.servingGrams)
    }

    func testOldSavedFoodsStillDecode() throws {
        let old = #"{"id":"x","name":"Oats","per100":{"kcal":380,"protein":13,"carbs":60,"fat":7,"fibre":10}}"#
        let item = try JSONDecoder().decode(FoodItem.self, from: Data(old.utf8))
        XCTAssertNil(item.measures)
    }
}
