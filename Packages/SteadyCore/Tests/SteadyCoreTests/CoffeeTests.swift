import XCTest
@testable import SteadyCore

final class CoffeeTests: XCTestCase {
    // Values copied from AUSNUT 2023 for the foods the builder uses.
    private let json = """
    {"source":"AUSNUT 2023","foods":[
     {"id":"F003041","name":"Coffee, espresso","kj":40,"p":1.7,"f":0.3,"c":0,"fi":0,"su":0,"density":1},
     {"id":"F003063","name":"Coffee, long black, double shot","kj":16,"p":0.7,"f":0.1,"c":0,"fi":0,"density":1},
     {"id":"F005634","name":"Milk, cow, fluid, regular fat (~3.5%)","kj":270,"p":3.3,"f":3.4,"c":5.4,"fi":0,"su":5.4,"density":1.03},
     {"id":"F008976","name":"Sugar, white, granulated or lump","kj":1600,"p":0,"f":0,"c":100,"fi":0,"su":100,"density":0.84}
    ]}
    """
    private func foods() throws -> GenericFoods { try GenericFoods(data: Data(json.utf8)) }

    func testFlatWhiteAddsCoffeeAndMilkByWeight() throws {
        let built = try XCTUnwrap(CoffeeBuilder.build(CoffeeOrder(style: .flatWhite), foods: foods()))
        // 80 mL espresso = 80 g; 150 mL milk x 1.03 = 154.5 g
        XCTAssertEqual(built.grams, 234.5, accuracy: 0.001)
        let kj = 80 * 0.40 + 154.5 * 2.70
        XCTAssertEqual(built.macros.kcal, kj / 4.184, accuracy: 0.01)
        XCTAssertEqual(built.macros.protein, 80 * 0.017 + 154.5 * 0.033, accuracy: 0.001)
        // Logging the whole cup gives the same totals as the parts.
        XCTAssertEqual(built.item.macros(grams: built.grams).kcal, built.macros.kcal, accuracy: 0.001)
        XCTAssertEqual(built.item.servingLabel, "1 cup, 230 mL")
    }

    func testSugarUsesFiveMillilitreTeaspoonAndDensity() throws {
        let built = try XCTUnwrap(CoffeeBuilder.build(CoffeeOrder(style: .doubleEspresso, sugarTsp: 1), foods: foods()))
        let sugar = try XCTUnwrap(built.parts.first { $0.name == "Sugar" })
        XCTAssertEqual(sugar.grams, 4.2, accuracy: 0.001)
        XCTAssertEqual(sugar.macros.carbs, 4.2, accuracy: 0.001)
    }

    func testLongPoursUseLongBlackAndCapsulesMultiply() throws {
        let o = CoffeeOrder(style: .mug, capsules: 2)
        XCTAssertEqual(o.milk, .noMilk)
        let built = try XCTUnwrap(CoffeeBuilder.build(o, foods: foods()))
        XCTAssertEqual(built.grams, 460, accuracy: 0.001)
        XCTAssertEqual(built.macros.kcal, 460 * 0.16 / 4.184, accuracy: 0.01)
    }

    func testSameOrderSameIdAndReadableName() {
        let a = CoffeeOrder(style: .latte, milk: .fullCream, sugarTsp: 0.5)
        XCTAssertEqual(CoffeeBuilder.id(a), CoffeeBuilder.id(a))
        XCTAssertNotEqual(CoffeeBuilder.id(a), CoffeeBuilder.id(CoffeeOrder(style: .latte)))
        XCTAssertEqual(CoffeeBuilder.name(a), "Latte (80 mL coffee, 200 mL full cream milk, 0.5 tsp sugar)")
    }

    func testMissingFoodGivesNoResultRatherThanAGuess() throws {
        let none = try GenericFoods(data: Data(#"{"source":"x","foods":[]}"#.utf8))
        XCTAssertNil(CoffeeBuilder.build(CoffeeOrder(style: .flatWhite), foods: none))
    }

    func testLegacyCoffeeOrdersAndNamedCapsuleIdentity() throws {
        let old = #"{"style":"espresso","brewMl":40,"capsules":1,"milk":"noMilk","milkMl":0,"sugarTsp":0}"#
        var order = try JSONDecoder().decode(CoffeeOrder.self, from: Data(old.utf8))
        XCTAssertNil(order.capsuleName)
        let genericID = CoffeeBuilder.id(order)
        order.capsuleName = "  Melozio  "
        XCTAssertTrue(CoffeeBuilder.name(order).contains("Melozio"))
        XCTAssertNotEqual(genericID, CoffeeBuilder.id(order))
        let saved = try JSONDecoder().decode(CoffeeOrder.self, from: JSONEncoder().encode(order))
        XCTAssertEqual(saved.namedCapsule, "Melozio")
        XCTAssertEqual(CoffeeBuilder.id(saved), CoffeeBuilder.id(order))
    }

}
