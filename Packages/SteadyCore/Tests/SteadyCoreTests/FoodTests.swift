import XCTest
@testable import SteadyCore

final class FoodTests: XCTestCase {
    let sample = """
    {"status":1,"product":{"code":"9300633603224","product_name":"Greek Yoghurt","brands":"Chobani, Other",
     "serving_quantity":"170","serving_size":"170 g",
     "nutriments":{"energy-kj_100g":"297","proteins_100g":9.6,"carbohydrates_100g":"4,1","fat_100g":0.2}}}
    """

    func testParsesProductWithKilojoulesAndStringNumbers() throws {
        let item = try XCTUnwrap(OpenFoodFacts.parseProduct(Data(sample.utf8)))
        XCTAssertEqual(item.name, "Greek Yoghurt")
        XCTAssertEqual(item.brand, "Chobani")
        XCTAssertEqual(item.per100.kcal, 297 / 4.184, accuracy: 0.01)
        XCTAssertEqual(item.per100.carbs, 4.1, accuracy: 0.001)
        XCTAssertEqual(item.servingGrams, 170)
        let m = item.macros(grams: 170)
        XCTAssertEqual(m.protein, 16.32, accuracy: 0.01)
    }

    func testDetailFromOpenFoodFacts() throws {
        let json = #"{"status":1,"product":{"code":"1","product_name":"Muesli bar","nutriments":{"energy-kcal_100g":420,"proteins_100g":7,"carbohydrates_100g":60,"fat_100g":15,"sugars_100g":28,"saturated-fat_100g":6,"salt_100g":0.5}}}"#
        let item = try XCTUnwrap(OpenFoodFacts.parseProduct(Data(json.utf8)))
        XCTAssertEqual(item.per100.sugar, 28)
        XCTAssertEqual(item.per100.satFat, 6)
        XCTAssertEqual(item.per100.sodium ?? 0, 200, accuracy: 0.01)     // 0.5 g salt is 200 mg sodium
        let m = item.macros(grams: 50)
        XCTAssertEqual(m.sugar ?? 0, 14, accuracy: 0.01)
        // Foods without detail don't turn the day's total into zero.
        let plain = Macros(kcal: 100)
        XCTAssertEqual((m + plain).sugar ?? 0, 14, accuracy: 0.01)
        XCTAssertNil((plain + plain).sugar)
    }

    func testOldSavedFoodsStillDecode() throws {
        let old = #"{"kcal":100,"protein":5,"carbs":10,"fat":2,"fibre":1}"#
        let p = try JSONDecoder().decode(Per100.self, from: Data(old.utf8))
        XCTAssertNil(p.sugar)
        XCTAssertEqual(p.kcal, 100)
    }

    func testMissingProductAndMissingEnergy() throws {
        XCTAssertNil(try OpenFoodFacts.parseProduct(Data(#"{"status":0}"#.utf8)))
        let noEnergy = #"{"status":1,"product":{"product_name":"X","nutriments":{"proteins_100g":1}}}"#
        XCTAssertNil(try OpenFoodFacts.parseProduct(Data(noEnergy.utf8)))
    }

    func testSearchSkipsUnusableProducts() throws {
        let json = #"{"products":[{"product_name":"Oats","nutriments":{"energy-kcal_100g":379,"proteins_100g":13}},{"product_name":""}]}"#
        let items = try OpenFoodFacts.parseSearch(Data(json.utf8))
        XCTAssertEqual(items.map(\.name), ["Oats"])
    }

    func testURLs() {
        XCTAssertNil(OpenFoodFacts.productURL(barcode: "123"))
        XCTAssertTrue(OpenFoodFacts.productURL(barcode: "9300633603224")!.absoluteString.contains("/product/9300633603224.json"))
        XCTAssertTrue(OpenFoodFacts.searchURL("weet bix")!.absoluteString.contains("tag_0=australia"))
    }

    func testMealSuggestion() {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        func at(_ h: Int) -> Date { cal.date(from: DateComponents(year: 2026, month: 11, day: 2, hour: h))! }
        XCTAssertEqual(MealSlot.suggested(for: at(7), calendar: cal), .breakfast)
        XCTAssertEqual(MealSlot.suggested(for: at(12), calendar: cal), .lunch)
        XCTAssertEqual(MealSlot.suggested(for: at(19), calendar: cal), .dinner)
        XCTAssertEqual(MealSlot.suggested(for: at(15), calendar: cal), .snacks)
    }

    func testMacrosAdd() {
        let a = Macros(kcal: 100, protein: 10), b = Macros(kcal: 50, fat: 2)
        XCTAssertEqual((a + b).kcal, 150)
        XCTAssertEqual((a + b).fat, 2)
    }
}
